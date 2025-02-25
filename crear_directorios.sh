#!/bin/bash
set -e  # Detiene el script si ocurre un error

# Crear los directorios necesarios
mkdir -p /home/andres/Quiz_Monroy_2004/A/{B,C,D,E,F,G} \
         /home/andres/Quiz_Monroy_2004/A/E/H \
         /home/andres/Quiz_Monroy_2004/A/F/I \
         /home/andres/Quiz_Monroy_2004/A/E/H/{J,K}

# Definir la ruta base donde se guardarán los archivos
BASE_DIR="/home/andres/Quiz_Monroy_2004/A/E/H/K"

# Asegurar permisos adecuados en la carpeta
chmod 755 "$BASE_DIR"

# Crear archivos si no existen
touch "$BASE_DIR/puertos_estado.txt" "$BASE_DIR/servicios_estado.txt" "$BASE_DIR/wifi_limpio.txt"

# Verificar si los comandos necesarios existen antes de ejecutarlos
for cmd in nmap nmcli rsync sshpass firefox; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd no está instalado." >> "$BASE_DIR/error.log"
        exit 1
    fi
done

# Analizar puertos abiertos y guardar en puertos_estado.txt
nmap -p- localhost -sT --reason | awk '
BEGIN { printf "%-10s %-10s %-20s %-10s %-15s\n", "PUERTO", "ESTADO", "SERVICIO", "PROTOCOLO", "MOTIVO"; 
        print "--------------------------------------------------------------------------"; }
/open|closed/ { 
    split($1, arr, "/");
    printf "%-10s %-10s %-20s %-10s %-15s\n", arr[1], $2, $3, arr[2], $4; 
}' > "$BASE_DIR/puertos_estado.txt"

# Obtener servicios en ejecución y guardar en servicios_estado.txt
systemctl list-units --type=service --all --no-pager | awk '
NR > 1 {
    split($1, arr, ".service");
    service = arr[1];
    estado = ($4 == "running") ? "UP" : "DOWN";
    cmd = "systemctl show -p MainPID " service " | cut -d= -f2"; cmd | getline pid; close(cmd);
    cmd = "systemctl is-enabled " service " 2>/dev/null"; cmd | getline habilitado; close(cmd);
    if (habilitado == "") habilitado = "unknown";
    printf "%-40s %-10s %-15s %-10s\n", service, estado, habilitado, pid;
}' > "$BASE_DIR/servicios_estado.txt"

# Obtener redes WiFi y guardar en wifi_limpio.txt
nmcli -t -f SSID,IN-USE,SIGNAL,FREQ,SECURITY dev wifi list | awk -F: '
BEGIN { printf "%-30s %-10s %-10s %-15s\n", "SSID", "POTENCIA", "FRECUENCIA", "SEGURIDAD";
        print "--------------------------------------------------------------"; }
{
    if ($1 != "")
        printf "%-30s %-10s %-10s %-15s\n", $1, $3 " dBm", $4 " GHz", ($5 == "WPA" || $5 == "WEP") ? "Encriptada" : "Abierta";
}' > "$BASE_DIR/wifi_limpio.txt"

# Crear archivo HTML en /var/www/html
HTML_FILE="/var/www/html/index.html"
cat <<EOF | sudo tee "$HTML_FILE" > /dev/null
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Quiz Monroy_2004</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin: 40px; }
        h1 { color: #2c3e50; }
        button { padding: 10px 20px; margin: 10px; cursor: pointer; border: none; background-color: #3498db; color: white; border-radius: 5px; }
        button:hover { background-color: #2980b9; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 5px; text-align: left; max-width: 600px; margin: auto; }
    </style>
</head>
<body>
    <h1>Quiz Monroy_2004</h1>
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

# Configurar la máquina remota
REMOTE_USER="andres"
REMOTE_IP="192.168.0.5"
REMOTE_PATH="/var/www/html"

# Enviar archivos a la máquina remota
sshpass -p "andres06271" rsync -avz /var/www/html/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH"

# Dar permisos correctos en la máquina remota
sshpass -p "andres06271" ssh "$REMOTE_USER@$REMOTE_IP" "sudo chmod -R 755 $REMOTE_PATH"

# Abrir la página en el navegador remoto
sshpass -p "andres06271" ssh -X "$REMOTE_USER@$REMOTE_IP" "DISPLAY=:0 firefox $REMOTE_PATH/index.html &"

# Reiniciar el servidor web
sudo systemctl restart apache2
