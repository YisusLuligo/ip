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
    Node.ping(nodo) == :pong
  end

  @doc """
  Obtiene la dirección IP local para conexiones.
  Mejorado para ser más consistente y confiable.
  """
  def obtener_ip_local do
    # Obtener todas las interfaces
    {_, direcciones} = :inet.getif()

    # Filtrar direcciones locales y seleccionar la más adecuada
    ip_cadena = case Enum.filter(direcciones, fn {ip, _, _} ->
      ip_cadena = :inet.ntoa(ip) |> to_string()
      # Excluir loopback, IPs de enlace local y direcciones IPv6
      not String.starts_with?(ip_cadena, "127.") and
      not String.starts_with?(ip_cadena, "169.254.") and
      not String.contains?(ip_cadena, ":")
    end) do
      [{ip, _, _} | _] ->
        :inet.ntoa(ip) |> to_string()
      _ ->
        # Si no encuentra una IP adecuada, obtener IP de manera más robusta
        case :os.type() do
          {:unix, :linux} ->
            {result, output} = System.cmd("hostname", ["-I"])
            primera_ip = String.trim(output) |> String.split() |> Enum.find(fn ip ->
              not String.starts_with?(ip, "127.") and
              not String.starts_with?(ip, "169.254.") and
              not String.contains?(ip, ":")
            end)
            primera_ip || "127.0.0.1"
          _ ->
            # Fallback a una IP más probable de funcionar en una red local
            "127.0.0.1"
        end
    end

    Logger.info("Usando IP local: #{ip_cadena}")
    ip_cadena
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
    random = :rand.uniform(1_000_000)
    pid_string = inspect(self()) |> String.replace(~r/[<>#]/, "")
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
end
