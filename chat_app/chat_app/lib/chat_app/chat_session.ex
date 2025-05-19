defmodule ChatSession do
  @moduledoc """
  Gestiona la sesión interactiva de chat para un cliente.
  """
  require Logger

  @doc """
  Inicia una sesión de chat para un usuario autenticado.
  """
  def iniciar_sesion(servidor_pid, username, nodo_servidor) do
    # Configurar para recibir mensajes
    Process.flag(:trap_exit, true)

    # Mostrar las salas disponibles
    mostrar_opciones_salas(servidor_pid, username, nodo_servidor)
  end

  @doc """
  Muestra las opciones de salas disponibles.
  """
  def mostrar_opciones_salas(servidor_pid, username, nodo_servidor) do
    # Obtener las salas disponibles
    salas = GenServer.call(servidor_pid, :listar_salas, 5000)  # Añadido timeout

    IO.puts("\n===== SALAS DE CHAT =====")
    IO.puts("Usuario actual: #{username}")
    IO.puts("Salas disponibles:")

    if Enum.empty?(salas) do
      IO.puts("  No hay salas disponibles.")
    else
      Enum.with_index(salas, 1) |> Enum.each(fn {sala, indice} ->
        IO.puts("  #{indice}. #{sala}")
      end)
    end

    IO.puts("\n#{length(salas) + 1}. Crear nueva sala")
    IO.puts("#{length(salas) + 2}. Salir")

    # Solicitar selección al usuario
    opcion = IO.gets("\nSeleccione una opción: ") |> String.trim()
    manejar_seleccion_sala(opcion, salas, servidor_pid, username, nodo_servidor)
  end

  @doc """
  Maneja la selección de sala del usuario.
  """
  def manejar_seleccion_sala(opcion, salas, servidor_pid, username, nodo_servidor) do
    case Integer.parse(opcion) do
      {num, _} when num >= 1 and num <= length(salas) ->
        # Unirse a sala existente
        sala_seleccionada = Enum.at(salas, num - 1)
        unirse_a_sala(servidor_pid, sala_seleccionada, username, nodo_servidor)

      {num, _} when num == length(salas) + 1 ->
        # Crear nueva sala
        nueva_sala = IO.gets("Nombre de la nueva sala: ") |> String.trim()
        crear_sala(servidor_pid, nueva_sala, username, nodo_servidor)

      {num, _} when num == length(salas) + 2 ->
        # Salir
        IO.puts("Saliendo del chat...")
        GenServer.cast({:global, :chat_servidor}, {:dar_baja, username})
        System.halt(0)

      _ ->
        IO.puts("Opción inválida. Intente de nuevo.")
        mostrar_opciones_salas(servidor_pid, username, nodo_servidor)
    end
  end

  @doc """
  Crea una nueva sala y se une a ella.
  """
  def crear_sala(servidor_pid, nombre_sala, username, nodo_servidor) do
    case GenServer.call(servidor_pid, {:crear_sala, username, nombre_sala}, 5000) do
      :ok ->
        IO.puts("Sala '#{nombre_sala}' creada exitosamente.")
        iniciar_sala_chat(servidor_pid, nombre_sala, username, nodo_servidor)

      {:error, :sala_existente} ->
        IO.puts("Ya existe una sala con ese nombre. Intente con otro nombre.")
        mostrar_opciones_salas(servidor_pid, username, nodo_servidor)

      {:error, razon} ->
        IO.puts("Error al crear sala: #{inspect(razon)}")
        mostrar_opciones_salas(servidor_pid, username, nodo_servidor)
    end
  end

  @doc """
  Une al usuario a una sala existente.
  """
  def unirse_a_sala(servidor_pid, nombre_sala, username, nodo_servidor) do
    case GenServer.call(servidor_pid, {:unirse_sala, username, nombre_sala}, 5000) do
      :ok ->
        IO.puts("Te has unido a la sala '#{nombre_sala}'.")
        iniciar_sala_chat(servidor_pid, nombre_sala, username, nodo_servidor)

      {:error, razon} ->
        IO.puts("Error al unirse a la sala: #{inspect(razon)}")
        mostrar_opciones_salas(servidor_pid, username, nodo_servidor)
    end
  end

  @doc """
  Inicia la interfaz de chat en una sala.
  """
  def iniciar_sala_chat(servidor_pid, nombre_sala, username, nodo_servidor) do
    # Mostrar historial de mensajes
    mensajes = GenServer.call(servidor_pid, {:obtener_historial, nombre_sala}, 10000)  # Timeout extendido

    if not Enum.empty?(mensajes) do
      IO.puts("\nHistorial de mensajes:")
      Enum.each(mensajes, fn {from, mensaje, timestamp} ->
        # Formatear timestamp
        hora_formateada = ChatUtils.formatear_timestamp(timestamp)
        if from == username do
          IO.puts("\e[36m[#{hora_formateada}] TÚ: #{mensaje}\e[0m")  # Azul claro
        else
          IO.puts("[#{hora_formateada}] #{from}: #{mensaje}")
        end
      end)
      IO.puts("")
    end

    IO.puts("\nEscribe tus mensajes. Comandos disponibles:")
    IO.puts("  /usuarios - Mostrar usuarios conectados")
    IO.puts("  /volver - Volver al menú de salas")
    IO.puts("  /historial - Ver historial de mensajes")
    IO.puts("  /ayuda - Mostrar esta ayuda")
    IO.puts("  /salir - Salir del chat")

    bucle_chat(servidor_pid, nombre_sala, username, nodo_servidor)
  end

  @doc """
  Bucle principal de chat en una sala.
  """
  def bucle_chat(servidor_pid, nombre_sala, username, nodo_servidor) do
    # Procesar mensajes entrantes
    procesar_mensajes_pendientes(servidor_pid, nombre_sala, username, nodo_servidor)

    # Solicitar entrada al usuario
    input = IO.gets("[#{nombre_sala}]> ") |> String.trim()

    case input do
      "/salir" ->
        IO.puts("Saliendo del chat...")
        GenServer.cast({:global, :chat_servidor}, {:dar_baja, username})
        System.halt(0)

      "/volver" ->
        mostrar_opciones_salas(servidor_pid, username, nodo_servidor)

      "/usuarios" ->
        usuarios = GenServer.call(servidor_pid, :listar_usuarios, 5000)
        IO.puts("\nUsuarios conectados:")
        Enum.each(usuarios, fn user ->
          if user == username do
            IO.puts("  - #{user} (TÚ)")
          else
            IO.puts("  - #{user}")
          end
        end)
        bucle_chat(servidor_pid, nombre_sala, username, nodo_servidor)

      "/historial" ->
        mensajes = GenServer.call(servidor_pid, {:obtener_historial, nombre_sala}, 10000)
        IO.puts("\nHistorial de mensajes:")
        if Enum.empty?(mensajes) do
          IO.puts("  No hay mensajes.")
        else
          Enum.each(mensajes, fn {from, mensaje, timestamp} ->
            hora_formateada = ChatUtils.formatear_timestamp(timestamp)
            if from == username do
              IO.puts("\e[36m[#{hora_formateada}] TÚ: #{mensaje}\e[0m")  # Azul claro
            else
              IO.puts("[#{hora_formateada}] #{from}: #{mensaje}")
            end
          end)
        end
        bucle_chat(servidor_pid, nombre_sala, username, nodo_servidor)

      "/ayuda" ->
        IO.puts("\nComandos disponibles:")
        IO.puts("  /usuarios - Mostrar usuarios conectados")
        IO.puts("  /volver - Volver al menú de salas")
        IO.puts("  /historial - Ver historial de la sala actual")
        IO.puts("  /ayuda - Mostrar esta ayuda")
        IO.puts("  /salir - Salir del chat")
        bucle_chat(servidor_pid, nombre_sala, username, nodo_servidor)

      mensaje ->
        # Enviar mensaje
        GenServer.cast(servidor_pid, {:enviar_mensaje, username, nombre_sala, mensaje})

        # Procesar mensajes entrantes
        procesar_mensajes_pendientes(servidor_pid, nombre_sala, username, nodo_servidor)

        bucle_chat(servidor_pid, nombre_sala, username, nodo_servidor)
    end
  end

  @doc """
  Maneja la reconexión en caso de desconexión.
  """
  def manejar_reconexion(servidor_pid, username, nodo_servidor, nombre_sala) do
    IO.puts("\n[!] Conexión perdida con el servidor. Intentando reconectar...")

    # Intentar reconectar hasta 5 veces con backoff exponencial
    reconectado = Enum.reduce_while(1..5, false, fn intento, _ ->
      IO.puts("Intento de reconexión #{intento}/5...")
      Process.sleep(1000 * :math.pow(2, intento - 1) |> round)  # Backoff exponencial

      # Primero verificar si el nodo está vivo
      if ChatUtils.nodo_vivo?(nodo_servidor) do
        # Luego verificar si el servidor está registrado globalmente
        servidor_pid = :global.whereis_name(:chat_servidor)
        if servidor_pid != :undefined do
          # Intentar reautenticar
          try do
            case GenServer.call(servidor_pid, {:autenticar, username, "", self(), Node.self()}, 5000) do
              {:ok, _} ->
                IO.puts("Reconexión exitosa!")
                {:halt, {true, servidor_pid}}
              _ ->
                {:cont, false}
            end
          catch
            :exit, _ -> {:cont, false}
          end
        else
          {:cont, false}
        end
      else
        # Intentar reconectar al nodo
        Node.connect(nodo_servidor)
        {:cont, false}
      end
    end)

    case reconectado do
      {true, nuevo_pid} ->
        # Si reconectamos exitosamente y teníamos una sala activa, volver a unirse
        if nombre_sala do
          GenServer.call(nuevo_pid, {:unirse_sala, username, nombre_sala}, 5000)
          IO.puts("Volviendo a la sala #{nombre_sala}...")
          iniciar_sala_chat(nuevo_pid, nombre_sala, username, nodo_servidor)
        else
          mostrar_opciones_salas(nuevo_pid, username, nodo_servidor)
        end
      _ ->
        IO.puts("\n[X] No se pudo reconectar después de varios intentos. Saliendo...")
        System.halt(1)
    end
  end

  # Procesa mensajes pendientes
  defp procesar_mensajes_pendientes(servidor_pid, nombre_sala, username, nodo_servidor) do
    receive do
      {:mensaje_chat, sala, from, mensaje, timestamp} ->
        # Formatear timestamp
        hora_formateada = ChatUtils.formatear_timestamp(timestamp)

        # Imprimir con formato para distinguir mejor los mensajes
        if from == username do
          IO.puts("\r\e[36m[#{sala}][#{hora_formateada}] TÚ: #{mensaje}\e[0m")  # Azul claro
        else
          IO.puts("\r\e[32m[#{sala}][#{hora_formateada}] #{from}: #{mensaje}\e[0m")  # Verde
        end

        IO.write("[#{nombre_sala}]> ")  # Volver a mostrar el prompt
        procesar_mensajes_pendientes(servidor_pid, nombre_sala, username, nodo_servidor)

      {:mensaje_sistema, mensaje} ->
        IO.puts("\r\e[33m[SISTEMA] #{mensaje}\e[0m")  # Amarillo
        IO.write("[#{nombre_sala}]> ")  # Volver a mostrar el prompt
        procesar_mensajes_pendientes(servidor_pid, nombre_sala, username, nodo_servidor)

      {:EXIT, _pid, reason} ->
        IO.puts("\r\e[31m[ERROR] La conexión se ha interrumpido: #{inspect(reason)}\e[0m")
        manejar_reconexion(servidor_pid, username, nodo_servidor, nombre_sala)

      {:desconexion_forzada, mensaje} ->
        IO.puts("\r\e[31m[AVISO] #{mensaje}\e[0m")
        IO.puts("Saliendo del chat...")
        System.halt(0)

      {:nodedown, _node} ->
        IO.puts("\r\e[31m[ERROR] Se ha perdido la conexión con el servidor\e[0m")
        manejar_reconexion(servidor_pid, username, nodo_servidor, nombre_sala)

      other ->
        Logger.debug("Mensaje no reconocido: #{inspect(other)}")
        procesar_mensajes_pendientes(servidor_pid, nombre_sala, username, nodo_servidor)

    after 0 ->
      :ok  # No hay más mensajes pendientes
    end
  end
end
