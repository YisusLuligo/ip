defmodule ChatApp do
  @moduledoc """
  Módulo principal para el sistema de chat distribuido.
  Permite iniciar el servidor o conectarse como cliente.
  """
  require Logger

  # Cookie para conexiones distribuidas
  @cookie :chat_distribuido_secreto

  @doc """
  Inicia el servidor de chat.
  """
  def iniciar_servidor do
    Logger.info("Iniciando servidor de chat...")

    # Verificar si el nodo ya está iniciado
    unless Node.alive?() do
      nombre_nodo = "chat_server@#{ChatUtils.obtener_ip_local()}"
      Node.start(String.to_atom(nombre_nodo))
      Node.set_cookie(@cookie)
      Logger.info("Nodo servidor iniciado como #{Node.self()}")
    end

    # Verificar que el nombre del nodo contiene "server"
    unless Atom.to_string(Node.self()) =~ "server" do
      Logger.warning("El nodo no incluye 'server' en su nombre, lo que podría afectar la detección automática")
    end

    # Crear directorio para datos persistentes si no existe
    File.mkdir_p!("datos_chat")

    # Iniciar el servidor
    {:ok, servidor_pid} = ChatServer.iniciar()

    # Esperar a que el servidor se inicialice completamente
    Process.sleep(500)

    # Crear salas predefinidas
    salas_existentes = ChatServer.listar_salas()

    unless "General" in salas_existentes do
      ChatServer.crear_sala("sistema", "General")
    end

    unless "Soporte" in salas_existentes do
      ChatServer.crear_sala("sistema", "Soporte")
    end

    # Mostrar información de conexión para clientes
    ip = ChatUtils.obtener_ip_local()
    Logger.info("Servidor iniciado en #{Node.self()} (#{ip})")
    Logger.info("Los clientes pueden conectarse usando: ChatApp.conectar('#{ip}')")

    {:ok, servidor_pid}
  end

  @doc """
  Conecta un cliente al servidor de chat.
  """
  def conectar(servidor_ip) do
  # Verificar si el nodo ya está iniciado
  unless Node.alive?() do
    # Obtener IP local (accesible desde la red)
    ip_local = ChatUtils.obtener_ip_local()

    # Nombre único para el cliente
    nombre_cliente = "chat_client_#{:rand.uniform(10000)}"
    nombre_nodo = String.to_atom("#{nombre_cliente}@#{ip_local}")

    # Iniciar nodo y establecer cookie
    Node.start(nombre_nodo)
    Node.set_cookie(@cookie)
    Logger.info("Nodo cliente iniciado como #{Node.self()}")

    # Imprimir información para debugging
    IO.puts("Nodo local: #{Node.self()}")
    IO.puts("Cookie: #{inspect(Node.get_cookie())}")
  end

  # Construir el nombre del nodo del servidor (nombre exacto)
  nodo_servidor = :"chat_server@#{servidor_ip}"
  IO.puts("Intentando conectar a: #{nodo_servidor}")

  # Verificar cookie
  IO.puts("Cookie local: #{inspect(Node.get_cookie())}")

  # Probar ping antes de conectar
  ping_result = Node.ping(nodo_servidor)
  IO.puts("Ping a #{nodo_servidor}: #{ping_result}")

  # Intentar conectar al servidor
  case Node.connect(nodo_servidor) do
    true ->
      Logger.info("Conectado al servidor de chat en #{nodo_servidor}")
      iniciar_interfaz_cliente(nodo_servidor)
    false ->
      Logger.error("No se pudo conectar al servidor en #{nodo_servidor}")
      IO.puts("\n[ERROR] No se pudo conectar al servidor en #{servidor_ip}.")
      IO.puts("Verifique que:")
      IO.puts("1. La dirección IP del servidor es correcta: #{servidor_ip}")
      IO.puts("2. El servidor está en ejecución")
      IO.puts("3. Ambos nodos usan la misma cookie (:chat_distribuido_secreto)")
      IO.puts("\nInténtelo de nuevo cuando el servidor esté disponible.")
      {:error, :fallo_conexion}
  end
end

  @doc """
  Inicia la interfaz interactiva del cliente.
  """
  def iniciar_interfaz_cliente(nodo_servidor \\ nil) do
    # Si no se proporciona un nodo de servidor, intentar encontrar uno
    nodo_servidor = nodo_servidor || encontrar_nodo_servidor()

    if nodo_servidor do
      IO.puts("\n===== CHAT DISTRIBUIDO =====")
      IO.puts("Conexión exitosa al servidor: #{nodo_servidor}")
      IO.puts("1. Iniciar sesión")
      IO.puts("2. Registrar nuevo usuario")
      IO.puts("3. Salir")
      IO.puts("============================\n")

      case IO.gets("Seleccione una opción (1-3): ") |> String.trim do
        "1" -> iniciar_sesion(nodo_servidor)
        "2" -> registrar_usuario(nodo_servidor)
        "3" ->
          IO.puts("Saliendo del sistema.")
          System.halt(0)
        _ ->
          IO.puts("Opción inválida. Intente de nuevo.")
          iniciar_interfaz_cliente(nodo_servidor)
      end
    else
      IO.puts("\n[ERROR] No se pudo encontrar un servidor.")
      IO.puts("Verifique que:")
      IO.puts("1. El servidor esté en ejecución")
      IO.puts("2. Utilice: ChatApp.conectar(\"IP_DEL_SERVIDOR\")")
      IO.puts("\nInténtelo de nuevo cuando el servidor esté disponible.")
      {:error, :servidor_no_encontrado}
    end
  end

  @doc """
  Inicia sesión con un usuario existente.
  """
  def iniciar_sesion(nodo_servidor) do
    username = IO.gets("Usuario: ") |> String.trim
    password = IO.gets("Contraseña: ") |> String.trim

    # Obtener el PID del servidor
    servidor_pid = :global.whereis_name(:chat_servidor)

    if servidor_pid != :undefined do
      # Intentar autenticar
      case GenServer.call(servidor_pid, {:autenticar, username, password, self(), Node.self()}) do
        {:ok, _} ->
          # Iniciar la sesión de chat
          ChatSession.iniciar_sesion(servidor_pid, username, nodo_servidor)
        {:error, :auth_fallida} ->
          IO.puts("Usuario o contraseña incorrectos. Intente de nuevo.")
          iniciar_sesion(nodo_servidor)
        {:error, razon} ->
          IO.puts("Error al iniciar sesión: #{inspect(razon)}")
          iniciar_interfaz_cliente(nodo_servidor)
      end
    else
      IO.puts("No se pudo conectar con el servidor. Intente de nuevo más tarde.")
      {:error, :servidor_no_disponible}
    end
  end

  @doc """
  Registra un nuevo usuario.
  """
  def registrar_usuario(nodo_servidor) do
    username = IO.gets("Nuevo usuario: ") |> String.trim
    password = IO.gets("Nueva contraseña: ") |> String.trim
    confirmar_password = IO.gets("Confirme contraseña: ") |> String.trim

    if password != confirmar_password do
      IO.puts("Las contraseñas no coinciden. Intente de nuevo.")
      registrar_usuario(nodo_servidor)
    else
      # Obtener el PID del servidor
      servidor_pid = :global.whereis_name(:chat_servidor)

      if servidor_pid != :undefined do
        # Intentar registrar
        case GenServer.call(servidor_pid, {:registrar_usuario, username, password, self(), Node.self()}) do
          {:ok, _} ->
            # Iniciar la sesión de chat
            ChatSession.iniciar_sesion(servidor_pid, username, nodo_servidor)
          {:error, :usuario_existente} ->
            IO.puts("El nombre de usuario ya está en uso. Intente con otro.")
            registrar_usuario(nodo_servidor)
          {:error, razon} ->
            IO.puts("Error al registrar: #{inspect(razon)}")
            iniciar_interfaz_cliente(nodo_servidor)
        end
      else
        IO.puts("No se pudo conectar con el servidor. Intente de nuevo más tarde.")
        {:error, :servidor_no_disponible}
      end
    end
  end

  @doc """
  Encuentra un nodo servidor disponible.
  """
  def encontrar_nodo_servidor do
    # Buscar usando registro global primero
    case :global.whereis_name(:chat_servidor) do
      :undefined ->
        # Luego buscar entre nodos conectados
        Enum.find(Node.list(), fn node ->
          Atom.to_string(node) |> String.contains?("server")
        end)
      pid ->
        # Si está registrado globalmente, obtener el nodo
        node(pid)
    end
  end
end
