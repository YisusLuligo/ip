#!/usr/bin/env bash
# iniciar_cliente.sh - Script para iniciar un cliente de chat
# Autor: Claude
# Fecha: Mayo 2025

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "==============================================="
echo "         INICIADOR DE CLIENTE DE CHAT          "
echo "==============================================="
echo -e "${NC}"

# Verificar parámetros
SERVIDOR_IP="$1"
if [ -z "$SERVIDOR_IP" ]; then
    echo -e "${YELLOW}No se proporcionó la IP del servidor. Intente detectarla automáticamente...${NC}"
    
    # Verificar si hay un servidor ejecutándose localmente
    IP_ADDR=$(hostname -I | awk '{print $1}')
    if [ -z "$IP_ADDR" ]; then
        IP_ADDR=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    fi
    
    if [ -z "$IP_ADDR" ]; then
        IP_ADDR="127.0.0.1"
    fi
    
    SERVIDOR_IP="$IP_ADDR"
    
    echo -e "${YELLOW}¿Es $SERVIDOR_IP la IP del servidor? [S/n]${NC}"
    read CONFIRM_IP
    if [[ $CONFIRM_IP =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Por favor ingrese la IP del servidor:${NC}"
        read SERVIDOR_IP
        if [ -z "$SERVIDOR_IP" ]; then
            echo -e "${RED}No se proporcionó una IP válida. Saliendo.${NC}"
            exit 1
        fi
    fi
fi

# Obtener IP local para el cliente
IP_LOCAL=$(hostname -I | awk '{print $1}')
if [ -z "$IP_LOCAL" ]; then
    IP_LOCAL=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
fi

if [ -z "$IP_LOCAL" ]; then
    IP_LOCAL="127.0.0.1"
    echo -e "${YELLOW}No se pudo determinar la IP local. Usando $IP_LOCAL${NC}"
fi

# Comprobar si Elixir está instalado
if ! command -v elixir &> /dev/null; then
    echo -e "${RED}Elixir no está instalado. Por favor, instale Elixir antes de continuar.${NC}"
    exit 1
fi

# Verificar el estado del servidor
echo -e "${YELLOW}Verificando conexión con el servidor $SERVIDOR_IP...${NC}"

# Intentar hacer ping al servidor
ping -c 1 "$SERVIDOR_IP" > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}Advertencia: No se puede hacer ping a $SERVIDOR_IP.${NC}"
    echo -e "${YELLOW}¿Desea continuar de todos modos? [s/N]${NC}"
    read CONTINUE
    if [[ ! $CONTINUE =~ ^[Ss]$ ]]; then
        echo -e "${RED}Operación cancelada.${NC}"
        exit 1
    fi
fi

# Compilar la aplicación
echo -e "${YELLOW}Compilando aplicación...${NC}"
cd "$(dirname "$0")" || exit 1
mix compile

if [ $? -ne 0 ]; then
    echo -e "${RED}Error al compilar la aplicación. Verifique los errores.${NC}"
    exit 1
fi

# Crear directorio de datos si no existe
mkdir -p datos_chat

# Determinar si EPMD está en ejecución y reiniciarlo si es necesario
epmd -names > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Iniciando EPMD...${NC}"
    epmd -daemon
    sleep 1
fi

# Generar un nombre único para el cliente
TIMESTAMP=$(date +%s%N)
RANDOM_NUM=$((RANDOM % 9999 + 1000))
CLIENT_NAME="cliente_${RANDOM_NUM}_${TIMESTAMP}@$IP_LOCAL"
COOKIE="chat_distribuido_secreto"

echo -e "${GREEN}Iniciando cliente con nombre: $CLIENT_NAME${NC}"
echo -e "${YELLOW}Conectando al servidor: $SERVIDOR_IP${NC}"
echo -e "${YELLOW}Cookie: $COOKIE${NC}"
echo ""
echo -e "${BLUE}Una vez que IEx inicie, ejecute:${NC}"
echo -e "${GREEN}ChatApp.conectar(\"$SERVIDOR_IP\")${NC}"
echo ""
echo -e "${YELLOW}Iniciando IEx...${NC}"

# Iniciar IEx con el nodo cliente
iex --name "$CLIENT_NAME" --cookie "$COOKIE" -S mix

# Al salir, mostrar mensaje de despedida
echo -e "${GREEN}Gracias por usar el chat. ¡Hasta pronto!${NC}"