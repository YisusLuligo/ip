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
  Verifica si un nodo está vivo con verificación extra.
  """
  def nodo_vivo?(nodo) do
    # Verificamos usando múltiples métodos para asegurar la detección adecuada
    try do
      ping_result = Node.ping(nodo)
      epmd_result = :net_adm.ping(nodo)

      # Intentar con la API :rpc para verificar comunicación
      rpc_result = :rpc.call(nodo, Process, :alive?, [self()])

      # Considerar vivo solo si al menos un método funciona
      Logger.debug("Verificación de nodo #{nodo}: Node.ping=#{ping_result}, net_adm=#{epmd_result}, rpc=#{inspect(rpc_result)}")

      ping_result == :pong || epmd_result == :pong || (is_boolean(rpc_result) && rpc_result)
    rescue
      e ->
        Logger.warning("Error al verificar nodo #{nodo}: #{inspect(e)}")
        false
    end
  end

  @doc """
  Obtiene la dirección IP local que se usará para conexiones.
  Implementación mejorada con detección robusta.
  """
  def obtener_ip_local do
    # Intentar obtener la IP no local más apropiada
    ip = obtener_ip_priorizada() || "127.0.0.1"

    # Verificar si es localhost
    if ip == "127.0.0.1" or ip == "localhost" do
      Logger.warning("ATENCIÓN: Usando IP local (#{ip}) - las conexiones solo funcionarán en este equipo")
      Logger.warning("Para conexiones entre equipos, verifica tu configuración de red")
    else
      Logger.info("Usando IP para conexiones: #{ip}")
    end

    ip
  end

  # Método para obtener la dirección IP en orden de prioridad
  defp obtener_ip_priorizada do
    # 1. Intentar obtener IP externa
    ip_externa = obtener_ip_externa()

    if ip_externa do
      ip_externa
    else
      # 2. Intentar interfaces de red
      {_, direcciones} = :inet.getif()

      # Filtrar y priorizar interfaces
      ips_validas = direcciones
      |> Enum.map(fn {ip, _, _} -> :inet.ntoa(ip) |> to_string() end)
      |> Enum.filter(fn ip ->
        # Filtrar IPs válidas y priorizarlas
        not String.starts_with?(ip, "127.") and
        not String.starts_with?(ip, "169.254.") and
        not String.contains?(ip, ":")
      end)

      # Priorizar IPs por rango (primero 192.168.x.x, luego 10.x.x.x, etc)
      ip_priorizada = ips_validas
      |> Enum.find(fn ip -> String.starts_with?(ip, "192.168.") end)

      ip_priorizada || List.first(ips_validas) || obtener_ip_sistema()
    end
  end

  # Obtener IP del sistema usando comandos específicos
  defp obtener_ip_sistema do
    case :os.type() do
      {:unix, :linux} ->
        obtener_ip_linux()
      {:unix, :darwin} ->
        obtener_ip_macos()
      {:win32, _} ->
        obtener_ip_windows()
      _ ->
        nil
    end
  end

  # Obtener IP en Linux
  defp obtener_ip_linux do
    try do
      {output, 0} = System.cmd("hostname", ["-I"])
      output
      |> String.trim()
      |> String.split()
      |> Enum.find(fn ip ->
        not String.starts_with?(ip, "127.") and
        not String.starts_with?(ip, "169.254.") and
        not String.contains?(ip, ":")
      end)
    rescue
      _ ->
        # Intento alternativo con ip addr
        try do
          {output, 0} = System.cmd("ip", ["addr"])
          case Regex.run(~r/inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*global/, output) do
            [_, ip] -> ip
            _ -> nil
          end
        rescue
          _ -> nil
        end
    end
  end

  # Obtener IP en macOS
  defp obtener_ip_macos do
    try do
      {output, 0} = System.cmd("ifconfig", [])
      case Regex.run(~r/en[0-9]:.*inet\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, output) do
        [_, ip] -> ip
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  # Obtener IP en Windows
  defp obtener_ip_windows do
    try do
      {output, 0} = System.cmd("ipconfig", [])
      case Regex.run(~r/IPv4.*?:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, output) do
        [_, ip] -> ip
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  # Obtener IP externa (solo para verificación)
  defp obtener_ip_externa do
    # Este método solo se usa como último recurso
    # y no debe depender de servicios externos en producción
    nil
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
  Genera un nombre único para un nodo cliente garantizado.
  """
  def generar_nombre_cliente do
    # Usar una combinación verdaderamente única
    timestamp = :os.system_time(:nanosecond)
    random = :rand.uniform(1_000_000_000)
    pid_string = inspect(self()) |> String.replace(~r/[^a-zA-Z0-9]/, "")
    node_suffix = Atom.to_string(Node.self()) |> String.split("@") |> List.first() |> String.replace(~r/[^a-zA-Z0-9]/, "")

    # Combinación de todos los elementos para garantizar unicidad
    "client_#{timestamp}_#{random}_#{node_suffix}_#{pid_string}"
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
  Configura el entorno para uso en chat distribuido.
  """
  def configurar_entorno_distribuido(tipo) do
    # Configuración base común
    :application.set_env(:kernel, :net_setuptime, 60)  # Más tiempo para conexión
    :application.set_env(:kernel, :dist_auto_connect, false)  # No auto-conectar

    case tipo do
      :servidor ->
        # Configuración específica para servidor
        :application.set_env(:kernel, :net_ticktime, 60)  # Más tiempo antes de detectar desconexiones
        :application.set_env(:kernel, :inet_dist_listen_min, 9000)
        :application.set_env(:kernel, :inet_dist_listen_max, 9100)

        # Para diagnóstico
        :application.set_env(:kernel, :error_logger, {:file, 'logs/server_error.log'})
        File.mkdir_p!("logs")

      :cliente ->
        # Configuración específica para cliente
        :application.set_env(:kernel, :net_ticktime, 60)
        :application.set_env(:kernel, :connect_all, false)  # No conectar con todos los nodos
        :application.set_env(:kernel, :inet_dist_listen_min, 10000)
        :application.set_env(:kernel, :inet_dist_listen_max, 10100)
    end

    # Aplicar cambios
    :net_kernel.stop()
    Process.sleep(500)

    :ok
  end

  @doc """
  Verifica y corrige posibles conflictos de nombre.
  """
  def verificar_conflictos_nombre(tipo) do
    # Limpiar caché EPMD
    if tipo == :cliente do
      System.cmd("epmd", ["-kill"])
      Process.sleep(1000)
      System.cmd("epmd", ["-daemon"])
    end

    # Verificar y reportar nodos existentes
    {output, _} = System.cmd("epmd", ["-names"])
    Logger.debug("Nodos EPMD actuales: #{output}")

    :ok
  end
end
