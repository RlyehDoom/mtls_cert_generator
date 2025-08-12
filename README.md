# MTLS Certificate Generator

Este proyecto permite generar certificados para entornos de desarrollo y pruebas usando un contenedor Docker. Incluye scripts para la gestión de variables de entorno y automatización del proceso de generación de certificados.

## Estructura del proyecto

- `entrypoint.sh`: Script principal del contenedor, gestiona acciones y variables.
- `default.vars`: Archivo con variables de entorno por defecto.
- `scripts/global_utils.sh`: Funciones reutilizables para recarga de variables y generación de certificados.
- `scripts/certificates/certificates.sh`: Script que realiza la generación de certificados.
- `Dockerfile`: Define la imagen Docker.

## Uso rápido

### 1. Construir la imagen Docker

```sh
docker build -t mtls_generator:1.0.0 .
```

### 2. Ejecutar el contenedor

#### Linux/macOS (Bash):
```sh
docker run -d --rm -v $(pwd)/certs:/app/certs -v $(pwd)/config:/app/config mtls_generator:1.0.0
```

#### Windows (PowerShell):
```powershell
docker run -d --rm -v ${PWD}/certs:/app/certs -v ${PWD}/config:/app/config mtls_generator:1.0.0
```

### 3. Ejecutar con nombre personalizado

#### Linux/macOS (Bash):
```sh
docker run -d --rm --name mtls_generator -v $(pwd)/certs:/app/certs -v $(pwd)/config:/app/config mtls_generator:1.0.0
```

#### Windows (PowerShell):
```powershell
docker run -d --rm --name mtls_generator -v ${PWD}/certs:/app/certs -v ${PWD}/config:/app/config mtls_generator:1.0.0
```


### 4. Personalizando variables de entorno

Puedes pasar variables al contenedor usando `-e`:

#### Linux/macOS (Bash):
```sh
docker run -d --rm -v $(pwd)/certs:/app/certs -v $(pwd)/config:/app/config -e CERT_CN="Mi CA personalizada" -e CERT_VALIDITY_DAYS=730 mtls_generator:1.0.0
```

#### Windows (PowerShell):
```powershell
docker run -d --rm -v ${PWD}/certs:/app/certs -v ${PWD}/config:/app/config -e CERT_CN="Mi CA personalizada" -e CERT_VALIDITY_DAYS=730 mtls_generator:1.0.0
```

### 5. Usando un archivo `.env`

Si tienes un archivo `.env` con tus variables:

#### Linux/macOS (Bash):
```sh
docker run -d --rm -v $(pwd)/certs:/app/certs -v $(pwd)/config:/app/config --env-file .env mtls_generator:1.0.0
```

#### Windows (PowerShell):
```powershell
docker run -d --rm -v ${PWD}/certs:/app/certs -v ${PWD}/config:/app/config --env-file .env mtls_generator:1.0.0
```

## Variables de configuración

El archivo `default.vars` contiene las variables que controlan la generación de certificados. A continuación se explica cada una:

| Variable                | Descripción                                                                 |
|-------------------------|-----------------------------------------------------------------------------|
| GENERATE_CERTIFICATES   | Si es `true`, habilita la generación de certificados.                        |
| CERT_CN                 | Nombre común (Common Name) de la CA raíz.                                   |
| CERT_ALT_NAMES          | Nombres alternativos (SAN) para el certificado, separados por coma.          |
| CERT_KEY_PASSWORD       | Contraseña para la clave privada del certificado.                            |
| CERT_PFX_PASSWORD       | Contraseña para el archivo PFX generado.                                     |
| CERT_SIZE               | Tamaño de la clave en bits (ejemplo: 2048).                                 |
| CERT_NAMES              | Nombre(s) del certificado a generar.                                         |
| CERT_TYPE               | Tipo de certificado (`server`, `client`, etc.).                              |
| CERT_VALIDITY_DAYS      | Días de validez del certificado.                                             |
| CERT_FRIENDLY_NAME      | Nombre descriptivo para el certificado (opcional, usado en algunos formatos).|
| CERT_PRESERVE_CA_FILES  | Si es `true`, conserva los archivos de la CA generados en el proceso.        |

Puedes modificar estos valores en el volumen `mtls_config` para personalizar la generación según tus necesidades.

Edita el archivo `default.vars` en la carpeta local `config` para cambiar los valores por defecto:

#### Linux/macOS (Bash):
```sh
vi ./config/default.vars
```

#### Windows (PowerShell):
```powershell
notepad ./config/default.vars
```

Ejemplo de contenido:
```
CERT_CN=Mi CA personalizada
CERT_VALIDITY_DAYS=730
```

## Ejecución directa en la consola del contenedor

Si accedes a la consola del contenedor, puedes ejecutar directamente los métodos:

#### Linux/macOS (acceso al contenedor):
```sh
docker exec -it <container_id> /bin/bash
reload_vars
generate_certs
```

#### Windows (acceso al contenedor):
```powershell
docker exec -it <container_id> /bin/bash
reload_vars
generate_certs
```

No es necesario hacer `source` si el contenedor ya carga `/app/scripts/global_utils.sh` automáticamente (por ejemplo, usando `/etc/profile.d/`).

Esto permite recargar variables y generar certificados manualmente en cualquier momento durante la vida del contenedor.

## Instalación de certificados en la máquina local (Windows)

El proyecto incluye un script PowerShell `certs-install.ps1` que permite descargar e instalar automáticamente los certificados generados desde el volumen Docker a tu máquina local Windows.

### Características del script:
- Descarga certificados desde volúmenes Docker
- Instala certificados PFX en el almacén local de Windows
- Instala certificados CA en el almacén de autoridades raíz de confianza
- Detecta automáticamente contraseñas comunes
- Compatible con PowerShell Core (multiplataforma)

### Uso básico:

#### 1. Listar certificados disponibles:
```powershell
pwsh -File certs-install.ps1 -ListOnly
```

#### 2. Listar certificados de un volumen específico:
```powershell
pwsh -File certs-install.ps1 -ListOnly -VolumeName "mTLS-certs"
```

#### 3. Instalar certificado específico:
```powershell
pwsh -File certs-install.ps1 -CertName "dev-env.pfx" -CertPass "Developer2077"
```

#### 4. Instalar con volumen personalizado:
```powershell
pwsh -File certs-install.ps1 -CertName "dev-env.pfx" -CertPass "Developer2077" -VolumeName "mi-volumen-certs"
```

#### 5. Instalar todos los certificados automáticamente:
```powershell
pwsh -File certs-install.ps1 -CertName "dev-env.pfx"
```

### Pasos completos para usar los certificados:

1. **Generar certificados en Docker:**
   ```powershell
   docker run -d --rm --name mtls_generator -v mTLS-certs:/app/certs -v mTLS-config:/app/config mtls_generator:1.0.0
   ```

2. **Esperar a que termine la generación** (verifica los logs):
   ```powershell
   docker logs mtls_generator
   ```

3. **Instalar certificados en Windows:**
   ```powershell
   pwsh -File certs-install.ps1 -CertName "dev-env.pfx" -VolumeName "mTLS-certs"
   ```

4. **Verificar instalación:** Los certificados aparecerán en:
   - `certmgr.msc` → Personal → Certificados (certificados cliente/servidor)
   - `certmgr.msc` → Autoridades de certificación raíz de confianza (certificados CA)

### Requisitos:
- PowerShell Core (pwsh) instalado
- Docker en funcionamiento
- Permisos de administrador para instalar certificados en el almacén del sistema

## Notas adicionales

- El script recarga forzosamente las variables de `/app/config/default.vars` si no están definidas.
- Puedes extender los scripts para nuevas funcionalidades.
- El contenedor puede mantenerse abierto usando `tail -f /dev/null` o un bucle infinito.

## Soporte y dudas

Para cualquier consulta, abre un issue en el repositorio o contacta a github.com/rlyehdoom.
