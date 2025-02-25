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
    <title>Información del Sistema</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin: 40px; }
        h1 { color: #2c3e50; }
        button { padding: 10px 20px; margin: 10px; cursor: pointer; border: none; background-color: #3498db; color: white; border-radius: 5px; }
        button:hover { background-color: #2980b9; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 5px; text-align: left; max-width: 600px; margin: auto; }
    </style>
</head>
<body>
    <h1>Información del Sistema</h1>
    <button onclick="cargarContenido('puertos_estado.txt')">Ver Puertos Abiertos</button>
    <button onclick="cargarContenido('servicios_estado.txt')">Ver Servicios en Ejecución</button>
    <button onclick="cargarContenido('wifi_limpio.txt')">Ver Redes WiFi</button>
    <div id="contenido">
        <pre id="datos"></pre>
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

    # Reiniciar el servidor web para aplicar los cambios
    sudo systemctl restart apache2

    echo "Datos guardados en: $BASE_DIR y HTML generado en $HTML_FILE"

    # Esperar 10 minutos antes de la siguiente ejecución
    sleep 60
done

