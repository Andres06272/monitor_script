#!/bin/bash
set -e  # Detiene el script si ocurre un error

# Configurar usuario y máquina remota
REMOTE_USER="lredes11"
REMOTE_IP="172.16.14.83"
REMOTE_PASS="lredes11"

while true; do
    # Definir la ruta base donde se guardarán los archivos
    BASE_DIR="/home/andres/Quiz_Monroy_2004/A/E/H/K"

    # Crear los directorios si no existen
    mkdir -p "$BASE_DIR"

    # Asegurar permisos adecuados en la carpeta
    chmod 755 "$BASE_DIR"

    # Crear los archivos si no existen
    touch "$BASE_DIR/puertos_estado.txt" "$BASE_DIR/servicios_estado.txt" "$BASE_DIR/wifi_limpio.txt"

    # Verificar si los comandos necesarios existen antes de ejecutarlos
    for cmd in nmap nmcli sshpass rsync; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: $cmd no está instalado." >> "$BASE_DIR/error.log"
            exit 1
        fi
    done

    # Procesar los puertos abiertos y cerrados y guardarlos en puertos_estado.txt
    nmap -p- localhost -sT --reason | awk '
    BEGIN { print "PUERTO ESTADO SERVICIO PROTOCOLO MOTIVO"; }
    /open|closed/ { 
        split($1, arr, "/");
        print arr[1], $2, $3, arr[2], $4; 
    }' > "$BASE_DIR/puertos_estado.txt"

    # Procesar todos los servicios en ejecución y guardarlos en servicios_estado.txt
    systemctl list-units --type=service --all --no-pager | awk '
    NR > 1 {
        split($1, arr, ".service");
        service = arr[1];

        estado = ($4 == "running") ? "UP" : "DOWN";

        cmd = "systemctl show -p MainPID " service " | cut -d= -f2"; 
        cmd | getline pid;
        close(cmd);

        cmd = "systemctl is-enabled " service " 2>/dev/null";
        cmd | getline habilitado;
        close(cmd);

        if (habilitado == "") habilitado = "unknown";

        print service, estado, habilitado, pid;
    }' > "$BASE_DIR/servicios_estado.txt"

    # Procesar las redes WiFi disponibles y guardarlas en wifi_limpio.txt
    nmcli -t -f SSID,IN-USE,SIGNAL,FREQ,SECURITY dev wifi list | awk -F: '
    BEGIN { print "SSID POTENCIA FRECUENCIA SEGURIDAD"; }
    {
        if ($1 != "")
            print $1, $3 "dBm", $4 "GHz", ($5 == "WPA" || $5 == "WEP") ? "Encriptada" : "Abierta";
    }' > "$BASE_DIR/wifi_limpio.txt"

    # Copiar los archivos al servidor web
    sudo cp "$BASE_DIR"/*.txt /var/www/html/
    sudo chmod 644 /var/www/html/*.txt

    # Generar el HTML en /var/www/html/index.html
    cat <<EOF | sudo tee /var/www/html/index.html > /dev/null
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Analizador de Red</title>
</head>
<body>
    <h1>Quiz MONROY_2004</h1>
    <button onclick="cargarContenido('puertos_estado.txt')">Mostrar Puertos</button>
    <button onclick="cargarContenido('servicios_estado.txt')">Ver Servicios</button>
    <button onclick="cargarContenido('wifi_limpio.txt')">Listar WiFi</button>
    <pre id="datos">Selecciona una opción...</pre>
    <script>
        function cargarContenido(archivo) {
            fetch(archivo)
            .then(response => response.text())
            .then(data => document.getElementById('datos').innerText = data)
            .catch(error => console.error('Error:', error));
        }
    </script>
</body>
</html>
EOF

    # Enviar archivos a la máquina remota
    sshpass -p "$REMOTE_PASS" rsync -avz -e "ssh -o StrictHostKeyChecking=no" /var/www/html/ "$REMOTE_USER@$REMOTE_IP:/home/$REMOTE_USER/html_temp"

    # Ejecutar comandos en la máquina remota
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" <<EOF
        echo "$REMOTE_PASS" | sudo -S bash <<EOS
        mkdir -p /var/www/html
        cp -r /home/$REMOTE_USER/html_temp/* /var/www/html/
        chmod -R 755 /var/www/html
        rm -rf /home/$REMOTE_USER/html_temp
        systemctl restart apache2
EOS
        # Abrir la GUI en la máquina remota
        export DISPLAY=:0
        nohup xdg-open "http://localhost" >/dev/null 2>&1 &
        disown
EOF

    echo "Datos guardados en: $BASE_DIR y HTML generado en /var/www/html/index.html"

    sleep 60
done

