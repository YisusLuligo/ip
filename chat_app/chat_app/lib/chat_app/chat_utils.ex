defmodule ChatUtils do
  @moduledoc """
  Funciones utilitarias para el sistema de chat.
  """
  require Logger

  @doc """
  Formatea un timestamp en milisegundos a una cadena legible.
  """
  def formatear_timestamp(timestamp) do
    {{año, mes, dia}, {hora, minuto, segundo}} =
      :calendar.system_time_to_universal_time(timestamp, :millisecond)

    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B",
                  [año, mes, dia, hora, minuto, segundo])
    |> to_string()
  end

  @doc """
  Verifica si un nodo está vivo.
  """
  def nodo_vivo?(nodo) do
    # Usar una combinación de métodos para verificar
    ping_result = Node.ping(nodo)
    epmd_result = :net_adm.ping(nodo)

    # Registro en log para depuración
    Logger.debug("Ping a #{nodo}: Node.ping=#{ping_result}, net_adm.ping=#{epmd_result}")

    # Devolver true solo si ambos métodos tuvieron éxito
    ping_result == :pong || epmd_result == :pong
  end

  @doc """
  Obtiene la dirección IP local para conexiones.
  Mejorado para ser más consistente y confiable.
  """
  def obtener_ip_local do
    # Obtener todas las interfaces
    {_, direcciones} = :inet.getif()

    # Filtrar direcciones locales y seleccionar la más adecuada
    direcciones_validas = Enum.filter(direcciones, fn {ip, _, _} ->
      ip_cadena = :inet.ntoa(ip) |> to_string()
      # Excluir loopback, IPs de enlace local y direcciones IPv6
      not String.starts_with?(ip_cadena, "127.") and
      not String.starts_with?(ip_cadena, "169.254.") and
      not String.contains?(ip_cadena, ":")
    end)

    # Mostrar todas las IPs disponibles para diagnóstico
    Logger.debug("IPs disponibles: #{inspect(direcciones_validas |> Enum.map(fn {ip, _, _} -> :inet.ntoa(ip) end))}")

    ip_cadena = case direcciones_validas do
      [{ip, _, _} | _] ->
        :inet.ntoa(ip) |> to_string()
      _ ->
        # Si no encuentra una IP adecuada, intentar métodos alternativos
        case :os.type() do
          {:unix, :linux} ->
            {result, output} = System.cmd("hostname", ["-I"])
            ips = String.trim(output) |> String.split()
            Logger.debug("IPs desde hostname -I: #{inspect(ips)}")

            # Buscar una IP adecuada en las opciones
            primera_ip = Enum.find(ips, fn ip ->
              not String.starts_with?(ip, "127.") and
              not String.starts_with?(ip, "169.254.") and
              not String.contains?(ip, ":")
            end)

            if primera_ip do
              Logger.debug("Usando IP desde hostname -I: #{primera_ip}")
              primera_ip
            else
              # Fallback a una IP configurada manualmente
              Logger.warning("No se encontró una IP adecuada, usando IP por defecto")
              # Intenta obtener la IP usando ifconfig o ip addr
              obtener_ip_alternativa() || "127.0.0.1"
            end
          {:unix, _} ->
            # Para otros Unix (macOS, FreeBSD)
            obtener_ip_alternativa() || "127.0.0.1"
          {:win32, _} ->
            # Para Windows
            {result, output} = System.cmd("ipconfig", [])
            # Extraer IPv4 de la salida de ipconfig
            case Regex.run(~r/IPv4.*?:\s*(\d+\.\d+\.\d+\.\d+)/, output) do
              [_, ip] ->
                Logger.debug("Usando IPv4 desde ipconfig: #{ip}")
                ip
              nil ->
                Logger.warning("No se pudo extraer IP de ipconfig, usando localhost")
                "127.0.0.1"
            end
          _ ->
            # Sistema desconocido
            "127.0.0.1"
        end
    end

    # Verificación adicional de la IP
    if ip_cadena == "127.0.0.1" or ip_cadena == "localhost" do
      Logger.warning("Usando IP local (#{ip_cadena}), las conexiones solo funcionarán en este equipo")
    else
      Logger.info("Usando IP local: #{ip_cadena}")
    end

    ip_cadena
  end

  # Método alternativo para obtener IP
  defp obtener_ip_alternativa do
    # Probar varios comandos para obtener la IP
    cmds = [
      {"ifconfig", []},
      {"ip", ["addr"]},
      {"networksetup", ["-getinfo", "Ethernet"]},
      {"networksetup", ["-getinfo", "Wi-Fi"]}
    ]

    Enum.find_value(cmds, fn {cmd, args} ->
      try do
        {output, 0} = System.cmd(cmd, args)
        # Buscar la primera IPv4 no local en la salida
        case Regex.run(~r/inet (?!127\.0\.0\.1)(\d+\.\d+\.\d+\.\d+)/, output) do
          [_, ip] -> ip
          nil -> nil
        end
      rescue
        _ -> nil
      end
    end)
  end

  @doc """
  Crea directorios para datos de persistencia.
  """
  def asegurar_directorio_datos do
    File.mkdir_p!("datos_chat")
  end

  @doc """
  Escribe un archivo de forma segura (atómica).
  """
  def escribir_archivo_seguro(ruta, datos) do
    # Asegurar que el directorio exista
    asegurar_directorio_datos()

    # Ruta completa
    ruta_completa = Path.join("datos_chat", ruta)

    # Escribir primero a un archivo temporal
    ruta_temp = "#{ruta_completa}.tmp"

    try do
      File.write!(ruta_temp, datos)
      File.rename(ruta_temp, ruta_completa)
      :ok
    rescue
      e ->
        Logger.error("Error escribiendo archivo #{ruta}: #{inspect(e)}")
        :error
    end
  end

  @doc """
  Lee un archivo de forma segura.
  """
  def leer_archivo_seguro(ruta) do
    ruta_completa = Path.join("datos_chat", ruta)

    try do
      case File.read(ruta_completa) do
        {:ok, binario} ->
          {:ok, binario}
        {:error, razon} ->
          Logger.warning("Error leyendo archivo #{ruta}: #{inspect(razon)}")
          {:error, razon}
      end
    rescue
      e ->
        Logger.error("Excepción leyendo archivo #{ruta}: #{inspect(e)}")
        {:error, :excepcion}
    end
  end

  @doc """
  Genera una cookie segura para la comunicación entre nodos.
  """
  def generar_cookie_segura do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @doc """
  Genera un nombre único para un nodo cliente.
  """
  def generar_nombre_cliente do
    # Usar una combinación de timestamp, random y PID para garantizar unicidad
    timestamp = :os.system_time(:millisecond)
    random = :rand.uniform(1_000_000_000)  # Aumentado para mayor unicidad
    pid_string = inspect(self()) |> String.replace(~r/[<>#\.:]/, "")
    "chat_client_#{timestamp}_#{random}_#{pid_string}"
  end

  @doc """
  Imprime un mensaje con código de color.
  """
  def imprimir_color(mensaje, color) do
    codigo_color = case color do
      :rojo -> "\e[31m"
      :verde -> "\e[32m"
      :amarillo -> "\e[33m"
      :azul -> "\e[36m"
      :reset -> "\e[0m"
      _ -> "\e[0m"
    end

    IO.puts("#{codigo_color}#{mensaje}\e[0m")
  end

  @doc """
  Configura valores del entorno distribuido para mejorar conectividad.
  """
  def configurar_entorno_distribuido do
    # Valores más permisivos para conexiones distribuidas
    :application.set_env(:kernel, :net_setuptime, 30)
    :application.set_env(:kernel, :net_ticktime, 30)
    :application.set_env(:kernel, :dist_auto_connect, :once)

    # Para diagnóstico, habilitar logging de eventos distribuidos
    :application.set_env(:kernel, :dist_debug, true)

    # Configurar límites de conexión más altos
    :application.set_env(:kernel, :dist_listen_min, 5000)
    :application.set_env(:kernel, :dist_listen_max, 6000)

    :ok
  end
end
