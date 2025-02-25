#!/bin/bash
set -e  # Detiene el script si ocurre un error

while true; do
    # Crear los directorios si no existen
    mkdir -p /home/andres/Quiz_Monroy_2004/A/{B,C,D,E,F,G} \
             /home/andres/Quiz_Monroy_2004/A/E/H \
             /home/andres/Quiz_Monroy_2004/A/F/I \
             /home/andres/Quiz_Monroy_2004/A/E/H/{J,K}

    # Definir la ruta base donde se guardarán los archivos
    BASE_DIR="/home/andres/Quiz_Monroy_2004/A/E/H/K"

    # Asegurar permisos adecuados en la carpeta
    chmod 755 "$BASE_DIR"

    # Crear los archivos si no existen
    touch "$BASE_DIR/puertos_estado.txt" "$BASE_DIR/servicios_estado.txt" "$BASE_DIR/wifi_limpio.txt"

    # Verificar si los comandos necesarios existen antes de ejecutarlos
    if ! command -v nmap &>/dev/null; then
        echo "Error: nmap no está instalado." >> "$BASE_DIR/error.log"
        exit 1
    fi

    if ! command -v nmcli &>/dev/null; then
        echo "Error: nmcli no está instalado." >> "$BASE_DIR/error.log"
        exit 1
    fi

    # Procesar los puertos abiertos y cerrados y guardarlos en puertos_estado.txt
    nmap -p- localhost -sT --reason | awk '
    BEGIN { printf "%-10s %-10s %-20s %-10s %-15s\n", "PUERTO", "ESTADO", "SERVICIO", "PROTOCOLO", "MOTIVO"; 
            print "--------------------------------------------------------------------------"; }
    /open|closed/ { 
        split($1, arr, "/");
        printf "%-10s %-10s %-20s %-10s %-15s\n", arr[1], $2, $3, arr[2], $4; 
    }' > "$BASE_DIR/puertos_estado.txt"

    # Procesar todos los servicios en ejecución y guardarlos en servicios_estado.txt
    {
        printf "%-40s %-10s %-15s %-10s\n", "SERVICIO", "ESTADO", "HABILITADO", "PID"
        echo "---------------------------------------------------------------------------------------------"

        systemctl list-units --type=service --all --no-pager | awk '
        NR > 1 {
            split($1, arr, ".service");
            service = arr[1];

            if ($4 == "running") {
                estado = "UP";
                cmd = "systemctl show -p MainPID " service " | cut -d= -f2"; 
                cmd | getline pid;
                close(cmd);
            } else {
                estado = "DOWN";
                pid = "-";
            }

            cmd = "systemctl is-enabled " service " 2>/dev/null";
            cmd | getline habilitado;
            close(cmd);

            if (habilitado == "") habilitado = "unknown";

            printf "%-40s %-10s %-15s %-10s\n", service, estado, habilitado, pid;
        }' | sort -k3,3 -k2,2r  
    } > "$BASE_DIR/servicios_estado.txt"

    # Procesar las redes WiFi disponibles y guardarlas en wifi_limpio.txt
    nmcli -t -f SSID,IN-USE,SIGNAL,FREQ,SECURITY dev wifi list | awk -F: '
    BEGIN { printf "%-30s %-10s %-10s %-15s\n", "SSID", "POTENCIA", "FRECUENCIA", "SEGURIDAD";
            print "--------------------------------------------------------------"; }
    {
        if ($1 != "")
            printf "%-30s %-10s %-10s %-15s\n", $1, $3 " dBm", $4 " GHz", ($5 == "WPA" || $5 == "WEP") ? "Encriptada" : "Abierta";
    }' > "$BASE_DIR/wifi_limpio.txt"

    # Copiar los archivos al servidor web (requiere sudo)
    sudo cp "$BASE_DIR"/*.txt /var/www/html/
    sudo chmod 644 /var/www/html/*.txt

    # Generar el HTML en /var/www/html/index.html
    HTML_FILE="/var/www/html/index.html"

    cat <<EOF | sudo tee "$HTML_FILE" > /dev/null
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Analizador de Red</title>
    <style>
        body {
            font-family: 'Verdana', sans-serif;
            background: #121212;
            color: #ffffff;
            text-align: center;
            margin: 40px;
        }
        h1 {
            color: #00c3ff;
        }
        .btn-container {
            display: flex;
            justify-content: center;
            gap: 15px;
            margin-top: 20px;
        }
        button {
            padding: 12px 25px;
            font-size: 16px;
            cursor: pointer;
            border: 2px solid #00c3ff;
            background: transparent;
            color: #00c3ff;
            border-radius: 25px;
            transition: all 0.3s ease;
        }
        button:hover {
            background: #00c3ff;
            color: #121212;
        }
        .content-box {
            background: #1e1e1e;
            padding: 15px;
            border-radius: 10px;
            max-width: 700px;
            margin: 30px auto;
            text-align: left;
            box-shadow: 0 0 10px rgba(0, 195, 255, 0.5);
        }
        pre {
            white-space: pre-wrap;
            word-wrap: break-word;
        }
    </style>
</head>
<body>
    <h1>Analizador de Red</h1>
    <div class="btn-container">
        <button onclick="cargarContenido('puertos_estado.txt')">Mostrar Puertos Disponibles</button>
        <button onclick="cargarContenido('servicios_estado.txt')">Ver Procesos Activos</button>
        <button onclick="cargarContenido('wifi_limpio.txt')">Listar Redes WiFi</button>
    </div>
    <div class="content-box">
        <pre id="datos">Selecciona una opción para ver la información...</pre>
    </div>
    <script>
        function cargarContenido(archivo) {
            fetch(archivo)
            .then(response => response.text())
            .then(data => document.getElementById('datos').innerText = data)
            .catch(error => console.error('Error cargando el archivo:', error));
        }
    </script>
</body>
</html>

EOF

# Configurar la IP, usuario y contraseña de la máquina remota
REMOTE_USER="lredes11"
REMOTE_IP="172.16.14.83"  # Cambia esto por la IP de la máquina remota
REMOTE_PASS="adminlredes11"
REMOTE_PATH="/var/www/html"

# Enviar los archivos con sshpass y rsync usando una carpeta temporal
sshpass -p "$REMOTE_PASS" rsync -avz -e "ssh -o StrictHostKeyChecking=no" /var/www/html/ "$REMOTE_USER@$REMOTE_IP:/home/$REMOTE_USER/html_temp"

# Dar permisos y mover los archivos a /var/www/html en la máquina remota
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" <<EOF
    echo '$REMOTE_PASS' | sudo -S mkdir -p /var/www/html
    echo '$REMOTE_PASS' | sudo -S cp -r /home/$REMOTE_USER/html_temp/* /var/www/html/
    echo '$REMOTE_PASS' | sudo -S chmod -R 755 /var/www/html
    echo '$REMOTE_PASS' | sudo -S rm -rf /home/$REMOTE_USER/html_temp
    echo '$REMOTE_PASS' | sudo -S systemctl restart apache2
EOF

    echo "Datos guardados en: $BASE_DIR y HTML generado en $HTML_FILE"

    # Esperar 10 minutos antes de la siguiente ejecución
    sleep 600
done

