# PowerShell Core script for PFX certificate installation from Docker volume
# Compatible with Windows, Linux and macOS
# Automatically downloads certificates from Docker volume to local system
# Usage: pwsh -File certs-install.ps1 [-CertName <certificate-filename>] [-CertPass <password>] [-VolumeName <docker-volume>] [-ListOnly]

param(
    [string]$CertPass,
    [string]$CertName,
    [string]$VolumeName = "mTLS-certs",
    [switch]$ListOnly
)

# Utilidad para mostrar mensajes con colores
function Show-Message {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    $colors = @{ Info = "Green"; Warning = "Yellow"; Error = "Red"; Header = "Cyan" }
    if ($Type -eq "Header") {
        Write-Host "===================================================" -ForegroundColor Cyan
        Write-Host " $Message" -ForegroundColor Cyan
        Write-Host "===================================================" -ForegroundColor Cyan
    } else {
        Write-Host $Message -ForegroundColor $colors[$Type]
    }
}

# Obtiene certificados desde el volumen Docker de forma simplificada
function Get-DockerCertificates {
    param(
        [string]$DockerVolumeName = "mTLS-certs"
    )
    
    try {
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Show-Message "Docker no encontrado" "Warning"
            return @()
        }
        
        $volumeInfo = docker volume inspect $DockerVolumeName 2>$null | ConvertFrom-Json
        if (-not $volumeInfo -or $volumeInfo.Count -eq 0) {
            Show-Message "Volumen Docker '$DockerVolumeName' no encontrado" "Warning"
            return @()
        }

        $tempContainer = "cert-temp-$(Get-Random)"
        $tempDir = if ($IsWindows) { Join-Path $env:TEMP "docker-certs" } elseif ($IsMacOS) { Join-Path $env:TMPDIR "docker-certs" } else { "/tmp/docker-certs" }
        
        try {
            Show-Message "Accediendo al volumen Docker..."

            # Limpiar y crear directorio temporal
            if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force }
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            # Crear contenedor temporal y copiar certificados
            docker run -d --name $tempContainer -v "${DockerVolumeName}:/certs" alpine:latest tail -f /dev/null 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { return @() }

            docker cp "${tempContainer}:/certs/." $tempDir 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempDir)) { return @() }

            Show-Message "Certificados copiados exitosamente a: $tempDir"

            # Obtener archivos .pfx y/o ca.crt
            $files = @(Get-ChildItem -Path $tempDir -Filter "*.pfx" -ErrorAction SilentlyContinue)
            $files += @(Get-ChildItem -Path $tempDir -Filter "ca.crt" -ErrorAction SilentlyContinue)
            return $files | ForEach-Object {
                [PSCustomObject]@{
                    Path = $_.FullName
                    Name = $_.Name
                    Size = $_.Length
                }
            }
        } finally {
            docker rm -f $tempContainer 2>$null | Out-Null
        }
    } catch {
        Show-Message "Error accediendo al volumen Docker: $($_.Exception.Message)" "Warning"
        return @()
    }
}

# Obtiene contraseña por defecto desde .env o valor predeterminado
function Get-DefaultPassword {
    if (Test-Path ".env") {
        $envContent = Get-Content ".env" | Where-Object { $_ -match "CERT_PFX_PASSWORD=" }
        if ($envContent) {
            return ($envContent -split "=")[1].Trim()
        }
    }
    return "icbanking123"
}

# Obtiene información del certificado probando contraseñas comunes
function Get-CertificateInfo {
    param(
        [string]$CertPath
    )
    
    $commonPasswords = @("", "Infocorp2025", "Infocorp2013", "Password01", "Password01.")
    
    foreach ($pwd in $commonPasswords) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath, $pwd)
            $cn = if ($cert.Subject -match "CN=([^,]+)") { $matches[1] } else { "N/A" }
            return @{
                CN = $cn
                FriendlyName = if ($cert.FriendlyName) { $cert.FriendlyName } else { "N/A" }
                Subject = $cert.Subject
                NotAfter = $cert.NotAfter
                Thumbprint = $cert.Thumbprint
            }
        } catch { continue }
    }

    return @{
        CN = "Desconocido (Contraseña requerida)"
        FriendlyName = "Desconocido (Contraseña requerida)"
        Subject = "Desconocido (Contraseña requerida)"
        NotAfter = "Desconocido"
        Thumbprint = "Desconocido"
    }
}

# Solicita contraseña al usuario mostrando info del certificado
function Get-UserPassword {
    param(
        [string]$CertPath,
        [string]$CertName
    )
    
    $certInfo = Get-CertificateInfo $CertPath
    
    Show-Message "Información del Certificado" "Header"
    Show-Message "  Archivo: $CertName"
    Show-Message "  CN: $($certInfo.CN)"
    Show-Message "  Nombre Amigable: $($certInfo.FriendlyName)"
    Show-Message "  Asunto: $($certInfo.Subject)"
    Show-Message "  Expira: $($certInfo.NotAfter)"
    Show-Message ""

    Write-Host "Ingrese la contraseña del certificado" -ForegroundColor Yellow
    Write-Host "Presione Enter para usar contraseña por defecto ($((Get-DefaultPassword)))" -ForegroundColor Yellow
    $input = Read-Host -AsSecureString "Contraseña"
    
    if ($input.Length -eq 0) {
        Show-Message "Usando contraseña por defecto" "Warning"
        return ConvertTo-SecureString -String (Get-DefaultPassword) -AsPlainText -Force
    }

    return $input
}

# Busca certificado por nombre con coincidencias exactas y parciales
function Find-CertificateByName {
    param(
        [string]$Name,
        [string]$DockerVolumeName = "mTLS-certs"
    )
    
    Show-Message "Buscando certificado: $Name"
    $Extension = [System.IO.Path]::GetExtension($Name).TrimStart('.')
    
    $certs = Get-DockerCertificates -DockerVolumeName $DockerVolumeName
    if ($certs.Count -eq 0) {
        Show-Message "No hay certificados PFX y/o CA.CRT en el volumen Docker" "Error"
        return $null
    }
    
    # Búsqueda exacta (prioridad alta)
    $exact = $certs | Where-Object { 
        $_.Name -eq $Name -or 
        $_.Name -eq "$Name.$Extension" -or 
        ([System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Name -and $_.Name.EndsWith(".pfx")) -or 
        ([System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Name -and $_.Name.EndsWith(".crt"))
    }
    
    if ($exact) {
        Show-Message "✅ Encontrado: $($exact.Name)"
        return $exact
    }
    
    # Búsqueda parcial
    $partial = $certs | Where-Object { $_.Name -like "*$Name*" }
    
    if ($partial.Count -eq 1) {
        Show-Message "✅ Coincidencia parcial: $($partial.Name)"
        return $partial
    } elseif ($partial.Count -gt 1) {
        Show-Message "⚠️ Múltiples coincidencias para '$Name':" "Warning"
        $partial | ForEach-Object { 
            $info = Get-CertificateInfo $_.Path
            Show-Message "  - $($_.Name) | CN: $($info.CN)"
        }
        Show-Message "Especifique el nombre exacto del archivo" "Warning"
        return $null
    }
    
    Show-Message "❌ No se encontró certificado con nombre '$Name'" "Error"
    Show-Message "Certificados disponibles:"
    $certs | ForEach-Object { 
        $info = Get-CertificateInfo $_.Path
        Show-Message "  - $($_.Name) | CN: $($info.CN)"
    }
    
    return $null
}

# Desinstala certificados por nombre amigable según el SO
function Remove-ExistingCertificates {
    param(
        [string]$FriendlyName
    )
    
    if ([string]::IsNullOrEmpty($FriendlyName)) { return }
    
    Show-Message "Desinstalando certificados existentes con nombre: '$FriendlyName'" "Header"
    
    if ($IsWindows) {
        Remove-WindowsCertificates $FriendlyName
    } elseif ($IsLinux) {
        Remove-LinuxCertificates
    } elseif ($IsMacOS) {
        Remove-MacOSCertificates $FriendlyName
    }
}

# Desinstala certificados de Windows (CurrentUser y LocalMachine)
function Remove-WindowsCertificates {
    param(
        [string]$FriendlyName
    )
    
    try {
        Show-Message "Buscando certificados en Windows con nombre: '$FriendlyName'"
        
        # Stores a revisar
        $stores = @(
            @{ Location = "CurrentUser"; Store = "My"; Name = "Personal (Usuario Actual)" },
            @{ Location = "CurrentUser"; Store = "Root"; Name = "Raíz Confiable (Usuario Actual)" },
            @{ Location = "LocalMachine"; Store = "My"; Name = "Personal (Máquina Local)" },
            @{ Location = "LocalMachine"; Store = "Root"; Name = "Raíz Confiable (Máquina Local)" }
        )
        
        foreach ($storeConfig in $stores) {
            try {
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeConfig.Store, $storeConfig.Location)
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                
                $certs = $store.Certificates | Where-Object { 
                    $_.FriendlyName -eq $FriendlyName -or 
                    ($_.FriendlyName -and $_.FriendlyName.Trim() -eq $FriendlyName.Trim())
                }
                
                if ($certs) {
                    Show-Message "Encontrados $($certs.Count) certificado(s) en $($storeConfig.Name)"
                    foreach ($cert in $certs) {
                        Show-Message "  Eliminando: $($cert.Subject) | Thumbprint: $($cert.Thumbprint)"
                        $store.Remove($cert)
                    }
                    Show-Message "✅ $($certs.Count) certificado(s) eliminados de $($storeConfig.Name)"
                }
                
                $store.Close()
            } catch {
                if ($storeConfig.Location -eq "LocalMachine") {
                    Show-Message "⚠️ No se pudo acceder a $($storeConfig.Name): $($_.Exception.Message)" "Warning"
                    Show-Message "⚠️ Puede requerir privilegios de administrador" "Warning"
                } else {
                    Show-Message "❌ Error en $($storeConfig.Name): $($_.Exception.Message)" "Error"
                }
            }
        }
    } catch {
        Show-Message "❌ Error desinstalando certificados: $($_.Exception.Message)" "Error"
    }
}

# Desinstala certificados de Linux
function Remove-LinuxCertificates {
    try {
        Show-Message "Buscando certificados icbanking en Linux..."
        $certFile = "/usr/local/share/ca-certificates/icbanking.crt"
        
        if (Test-Path $certFile) {
            Show-Message "Encontrado: $certFile"
            Show-Message "Eliminando certificado del almacén del sistema..."
            
            Invoke-Expression "sudo rm -f '$certFile'"
            if ($LASTEXITCODE -eq 0) {
                Invoke-Expression "sudo update-ca-certificates"
                if ($LASTEXITCODE -eq 0) {
                    Show-Message "✅ Certificado eliminado del almacén del sistema"
                } else {
                    Show-Message "❌ Error actualizando almacén de certificados" "Error"
                }
            } else {
                Show-Message "❌ Error eliminando archivo de certificado" "Error"
            }
        } else {
            Show-Message "No se encontró certificado en el almacén del sistema"
        }
    } catch {
        Show-Message "❌ Error desinstalando certificado: $($_.Exception.Message)" "Error"
    }
}

# Desinstala certificados de macOS
function Remove-MacOSCertificates {
    param(
        [string]$FriendlyName
    )
    
    try {
        Show-Message "Buscando certificados con nombre '$FriendlyName' en macOS..."
        
        $searchResult = Invoke-Expression "security find-certificate -a -c '$FriendlyName' /Library/Keychains/System.keychain" 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $searchResult) {
            Show-Message "Encontrados certificado(s) con nombre '$FriendlyName' en System Keychain"
            Show-Message "Nota: Se le puede solicitar contraseña de administrador"
            
            Invoke-Expression "sudo security delete-certificate -c '$FriendlyName' /Library/Keychains/System.keychain"
            
            if ($LASTEXITCODE -eq 0) {
                Show-Message "✅ Certificado(s) eliminados del System Keychain"
            } else {
                Show-Message "❌ Error eliminando certificado(s) del System Keychain" "Error"
            }
        } else {
            Show-Message "No se encontraron certificados con nombre '$FriendlyName' en System Keychain"
        }
    } catch {
        Show-Message "❌ Error desinstalando certificado: $($_.Exception.Message)" "Error"
    }
}

function Install-PfxCertificate {
    param(
        [string]$CertPath,
        [SecureString]$Password
    )
    
    try {
        Show-Message "Instalando certificado PFX: $CertPath" "Header"
        
        # Validar contraseña antes de proceder
        $plainPassword = [System.Net.NetworkCredential]::new('', $Password).Password
        $testCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath, $plainPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)
        Show-Message "✅ Contraseña validada exitosamente"
        Show-Message "CN del certificado: $($testCert.Subject)"
        Show-Message "Friendly Name: $($testCert.FriendlyName)"
        
        # Obtener información del certificado
        $certInfo = Get-CertificateInfo -CertPath $CertPath
        Show-Message "Información del certificado:"
        Show-Message "  Subject: $($certInfo.Subject)"
        Show-Message "  Friendly Name: '$($certInfo.FriendlyName)'"
        Show-Message "  Válido hasta: $($certInfo.NotAfter)"
        
        # Desinstalar certificados existentes con el mismo friendly name
        if (-not [string]::IsNullOrEmpty($testCert.FriendlyName)) {
            Remove-ExistingCertificates -FriendlyName $testCert.FriendlyName
        }
        
        # Crear objeto de certificado con toda la información necesaria
        $certificateObject = [PSCustomObject]@{
            Name = [System.IO.Path]::GetFileName($CertPath)
            Path = $CertPath
            FriendlyName = $testCert.FriendlyName
            Password = $plainPassword
            Subject = $testCert.Subject
            NotAfter = $testCert.NotAfter
        }
        
        # Instalar según la plataforma
        Install-Certificates -Certificates @($certificateObject)
        
        return $certificateObject
    } catch {
        Show-Message "❌ Error instalando certificado PFX: $($_.Exception.Message)" "Error"
        return $null
    }
}

# Instala certificados según el SO detectado
function Install-Certificates {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject[]]$Certificates
    )
    
    Show-Message "Instalando $($Certificates.Count) certificado(s) según el SO detectado..." "Header"
    
    foreach ($cert in $Certificates) {
        Show-Message "Procesando: $($cert.FriendlyName)"
        
        if ($IsWindows) {
            Install-WindowsCertificate -Certificate $cert
        } elseif ($IsLinux) {
            Install-LinuxCertificate -Certificate $cert
        } elseif ($IsMacOS) {
            Install-MacOSCertificate -Certificate $cert
        } else {
            Show-Message "❌ Sistema operativo no soportado" "Error"
        }
    }
}

# Instalación específica para Windows
function Install-WindowsCertificate {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Certificate
    )
    
    try {
        Show-Message "Instalando '$($Certificate.FriendlyName)' en Windows..."
        
        # Crear objeto X509Certificate2 con contraseña
        $x509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Certificate.Path, $Certificate.Password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)
        
        # Asignar nombre amigable si está vacío
        if ([string]::IsNullOrEmpty($x509.FriendlyName)) {
            $x509.FriendlyName = $Certificate.FriendlyName
        }
        
        Show-Message "  Detalles del certificado:"
        Show-Message "    Subject: $($x509.Subject)"
        Show-Message "    Friendly Name: '$($x509.FriendlyName)'"
        Show-Message "    Thumbprint: $($x509.Thumbprint)"
        Show-Message "    Válido desde: $($x509.NotBefore)"
        Show-Message "    Válido hasta: $($x509.NotAfter)"
        Show-Message "    Tiene clave privada: $($x509.HasPrivateKey)"
        
        # Detectar stores según el tipo de certificado
        $stores = Get-WindowsStoresForCertificate $x509
        
        foreach ($storeConfig in $stores) {
            try {
                Show-Message "  Instalando en: $($storeConfig.Name)"
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeConfig.Store, $storeConfig.Location)
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                $store.Add($x509)
                $store.Close()
                
                Show-Message "  ✅ Instalado correctamente en $($storeConfig.Name)"
            } catch {
                if ($storeConfig.Location -eq "LocalMachine") {
                    Show-Message "  ⚠️ No se pudo instalar en $($storeConfig.Name): $($_.Exception.Message)" "Warning"
                    Show-Message "  ⚠️ Puede requerir privilegios de administrador" "Warning"
                } else {
                    Show-Message "  ❌ Error en $($storeConfig.Name): $($_.Exception.Message)" "Error"
                }
            }
        }
        
        return $x509
    } catch {
        Show-Message "❌ Error instalando certificado Windows: $($_.Exception.Message)" "Error"
        return $null
    }
}

# Determina los stores apropiados para un certificado en Windows
function Get-WindowsStoresForCertificate {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$cert)
    
    $stores = @()
    
    # Si tiene clave privada, va al Personal store
    if ($cert.HasPrivateKey) {
        $stores += @{ Location = "CurrentUser"; Store = "My"; Name = "Personal (Usuario Actual)" }
        $stores += @{ Location = "LocalMachine"; Store = "My"; Name = "Personal (Máquina Local)" }
    }
    
    # Si es CA o self-signed, también al Root store
    if ($cert.Subject -eq $cert.Issuer -or $cert.Extensions["2.5.29.19"]) {
        $stores += @{ Location = "CurrentUser"; Store = "Root"; Name = "Raíz Confiable (Usuario Actual)" }
        $stores += @{ Location = "LocalMachine"; Store = "Root"; Name = "Raíz Confiable (Máquina Local)" }
    }
    
    return $stores
}

# Instalación específica para Linux
function Install-LinuxCertificate {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Certificate
    )
    
    try {
        Show-Message "Instalando '$($Certificate.FriendlyName)' en Linux..."
        
        # Extraer certificado en formato PEM
        $x509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Certificate.Path, $Certificate.Password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
        
        $certPem = "-----BEGIN CERTIFICATE-----`n"
        $certPem += [System.Convert]::ToBase64String($x509.RawData, [System.Base64FormattingOptions]::InsertLineBreaks)
        $certPem += "`n-----END CERTIFICATE-----"
        
        # Guardar en directorio temporal primero
        $tempCertFile = "/tmp/icbanking_temp.crt"
        $finalCertFile = "/usr/local/share/ca-certificates/icbanking.crt"
        
        Show-Message "  Creando archivo temporal: $tempCertFile"
        Set-Content -Path $tempCertFile -Value $certPem -Encoding UTF8
        
        # Mover al directorio del sistema con sudo
        Show-Message "  Moviendo al almacén del sistema: $finalCertFile"
        Invoke-Expression "sudo cp '$tempCertFile' '$finalCertFile'"
        
        if ($LASTEXITCODE -eq 0) {
            # Actualizar el almacén de certificados del sistema
            Show-Message "  Actualizando almacén de certificados..."
            Invoke-Expression "sudo update-ca-certificates"
            
            if ($LASTEXITCODE -eq 0) {
                Show-Message "  ✅ Certificado instalado en el almacén del sistema"
            } else {
                Show-Message "  ❌ Error actualizando almacén de certificados" "Error"
            }
        } else {
            Show-Message "  ❌ Error copiando certificado al almacén del sistema" "Error"
        }
        
        # Limpiar archivo temporal
        if (Test-Path $tempCertFile) {
            Remove-Item $tempCertFile -Force
        }
        
    } catch {
        Show-Message "❌ Error instalando certificado Linux: $($_.Exception.Message)" "Error"
    }
}

# Instalación específica para macOS
function Install-MacOSCertificate {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Certificate
    )
    
    try {
        Show-Message "Instalando '$($Certificate.FriendlyName)' en macOS..."
        Show-Message "Nota: Se le puede solicitar contraseña de administrador"
        
        # Instalar certificado en System Keychain
        Invoke-Expression "sudo security add-trusted-cert -d -r trustRoot -k '/Library/Keychains/System.keychain' '$($Certificate.Path)'"
        
        if ($LASTEXITCODE -eq 0) {
            Show-Message "  ✅ Certificado instalado en System Keychain como confiable"
        } else {
            Show-Message "  ❌ Error instalando certificado en System Keychain" "Error"
        }
        
    } catch {
        Show-Message "❌ Error instalando certificado macOS: $($_.Exception.Message)" "Error"
    }
}


# Muestra certificados instalados según el SO
function Get-InstalledCertificates {
    param(
        [string]$DockerVolumeName = "mTLS-certs"
    )
    
    Show-Message "Certificados PFX Instalados ICBanking" "Header"
    
    # Mostrar certificados PFX del volumen Docker
    Show-Message "Verificando volumen Docker para certificados PFX..."
    $volumeCerts = Get-DockerCertificates -DockerVolumeName $DockerVolumeName
    if ($volumeCerts.Count -gt 0) {
        Show-Message "Certificados PFX disponibles en volumen Docker '$DockerVolumeName':"
        foreach ($cert in $volumeCerts) {
            # Obtener información del certificado
            $certInfo = Get-CertificateInfo -CertPath $cert.Path
            Show-Message "  - $($cert.Name)"
            Show-Message "    CN: $($certInfo.CN)"
            Show-Message "    Friendly Name: $($certInfo.FriendlyName)"
            Show-Message "    Subject: $($certInfo.Subject)"
            Show-Message "    Tamaño: $([math]::Round($cert.Size/1KB, 2)) KB"
            Show-Message "    Expira: $($certInfo.NotAfter)"
        }
        Show-Message ""
    } else {
        Show-Message "❌ No se encontraron certificados PFX en el volumen Docker '$DockerVolumeName'"
        Show-Message ""
    }
    
    # Mostrar certificados instalados por SO
    if ($IsWindows) {
        Show-Message "Verificando Almacenes de Certificados Windows..."
        Get-WindowsInstalledCertificates
    } elseif ($IsLinux) {
        Show-Message "Verificando almacén de certificados Linux..."
        Get-LinuxInstalledCertificates
    } elseif ($IsMacOS) {
        Show-Message "Verificando Keychain de macOS..."
        Get-MacOSInstalledCertificates
    }
}

# Obtiene certificados instalados en Windows
function Get-WindowsInstalledCertificates {
    # Verificar Personal store
    $personalCerts = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object { 
        $_.Subject -like "*icbanking*" -or $_.Subject -like "*localhost*" 
    }
    if ($personalCerts) {
        Show-Message "Personal Store (Usuario Actual):"
        $personalCerts | ForEach-Object { 
            $friendlyName = if ($_.FriendlyName) { $_.FriendlyName } else { "N/A" }
            Show-Message "  - Subject: $($_.Subject)"
            Show-Message "    Friendly Name: $friendlyName"
            Show-Message "    Thumbprint: $($_.Thumbprint)"
            Show-Message "    Expira: $($_.NotAfter)"
        }
    } else {
        Show-Message "No se encontraron certificados ICBanking en Personal Store"
    }
    
    # Verificar Root store
    $rootCerts = Get-ChildItem -Path "Cert:\CurrentUser\Root" | Where-Object { 
        $_.Subject -like "*icbanking*" -or $_.Subject -like "*localhost*" 
    }
    if ($rootCerts) {
        Show-Message "Trusted Root Store (Usuario Actual):"
        $rootCerts | ForEach-Object { 
            $friendlyName = if ($_.FriendlyName) { $_.FriendlyName } else { "N/A" }
            Show-Message "  - Subject: $($_.Subject)"
            Show-Message "    Friendly Name: $friendlyName"
            Show-Message "    Thumbprint: $($_.Thumbprint)"
        }
    } else {
        Show-Message "No se encontraron certificados ICBanking en Trusted Root Store"
    }
}

# Obtiene certificados instalados en Linux
function Get-LinuxInstalledCertificates {
    $certFile = "/usr/local/share/ca-certificates/icbanking.crt"
    if (Test-Path $certFile) {
        Show-Message "Almacén del Sistema:"
        Show-Message "  - Archivo: $certFile"
        Show-Message "  - Estado: Instalado"
    } else {
        Show-Message "No se encontraron certificados ICBanking en el almacén del sistema"
    }
}

# Obtiene certificados instalados en macOS
function Get-MacOSInstalledCertificates {
    try {
        $searchResult = Invoke-Expression "security find-certificate -a -c 'icbanking' /Library/Keychains/System.keychain" 2>$null
        if ($LASTEXITCODE -eq 0 -and $searchResult) {
            Show-Message "System Keychain:"
            Show-Message "  - Certificados ICBanking encontrados"
        } else {
            Show-Message "No se encontraron certificados ICBanking en System Keychain"
        }
    } catch {
        Show-Message "Error verificando System Keychain: $($_.Exception.Message)"
    }
}

# Utilidades auxiliares consolidadas
function ConvertTo-SecurePassword {
    param(
        [string]$PlainTextPass
    )
    
    if ([string]::IsNullOrEmpty($PlainTextPass)) { return $null }
    return ConvertTo-SecureString -String $PlainTextPass -AsPlainText -Force
}

function Invoke-WithTimeout {
    param([ScriptBlock]$ScriptBlock, [int]$TimeoutSeconds = 30, [string]$Operation = "Operation")
    try {
        Show-Message "Iniciando $Operation (timeout: ${TimeoutSeconds}s)..."
        $job = Start-Job -ScriptBlock $ScriptBlock
        
        if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            Show-Message "✅ $Operation completado exitosamente"
            return $result
        } else {
            Show-Message "❌ $Operation tardó más de ${TimeoutSeconds} segundos" "Error"
            Stop-Job -Job $job; Remove-Job -Job $job
            return $null
        }
    } catch {
        Show-Message "❌ Error en $Operation : $($_.Exception.Message)" "Error"
        return $null
    }
}

# Lógica principal de ejecución
try {
    Show-Message "Herramienta de Instalación de Certificados PFX" "Header"
    
    if ($ListOnly) {
        Get-InstalledCertificates -DockerVolumeName $VolumeName
        return
    }
    
    # CertName es requerido para instalación
    if (-not $CertName) {
        Show-Message "❌ El parámetro CertName es requerido para instalación" "Error"
        Show-Message "Uso: pwsh -File init-certs-install.ps1 -CertName <nombre-certificado> [-CertPass <contraseña>]" "Error"
        Show-Message "  o: pwsh -File init-certs-install.ps1 -ListOnly" "Error"
        Show-Message "Parámetros:"
        Show-Message "  -CertName    : Nombre del archivo de certificado a instalar"
        Show-Message "  -CertPass    : Contraseña para el certificado (opcional)"
        Show-Message "  -ListOnly    : Solo listar certificados disponibles"
        exit 1
    }
    
    # Buscar certificado por nombre
    $foundResult = Find-CertificateByName -Name $CertName -DockerVolumeName $VolumeName
    if (-not $foundResult) {
        Show-Message "❌ Archivo de certificado '$CertName' no encontrado" "Error"
        Show-Message "Use -ListOnly para ver archivos de certificado disponibles"
        exit 1
    }
    
    $CertPath = $foundResult.Path
    Show-Message "Usando certificado: $($foundResult.Name) en $CertPath"

    if (-not (Test-Path $CertPath)) {
        Show-Message "❌ Archivo de certificado no encontrado: $CertPath" "Error"
        exit 1
    }

    $extension = [System.IO.Path]::GetExtension($CertPath).ToLowerInvariant()

    if ($extension -eq ".pfx") {
        # Determinar contraseña
        $SecurePassword = $null
        if ($CertPass) {
            $SecurePassword = ConvertTo-SecurePassword -PlainTextPass $CertPass
            Show-Message "Usando contraseña proporcionada"
        } else {
            $SecurePassword = Get-UserPassword -CertPath $CertPath -CertName (Split-Path $CertPath -Leaf)
        }

        # Instalar certificado PFX
        $result = Install-PfxCertificate -CertPath $CertPath -Password $SecurePassword

        Show-Message "Instalación Completa" "Header"
        if ($null -ne $result) {
            Show-Message "✅ Proceso de instalación de certificado PFX completado exitosamente"
            
            # Buscar e instalar CA automáticamente
            Show-Message "Buscando e instalando CA correspondiente..." "Header"
            $caCert = Get-DockerCertificates -DockerVolumeName $VolumeName | Where-Object { $_.Name -eq "ca.crt" }
            if ($caCert) {
                Show-Message "Encontrado certificado CA: $($caCert.Name)"
                Remove-ExistingCertificates -FriendlyName "ICBanking Development CA"
                $caObject = [PSCustomObject]@{
                    Name = $caCert.Name
                    Path = $caCert.Path
                    FriendlyName = "ICBanking Development CA"
                    Password = $null
                    Subject = "CA"
                    NotAfter = $null
                }
                Install-Certificates -Certificates @($caObject)
                Show-Message "✅ Certificado CA instalado exitosamente"
                Show-Message "   Esto debería resolver los errores de 'net::ERR_CERT_AUTHORITY_INVALID'" "Info"
            } else {
                Show-Message "⚠️ No se encontró certificado CA (ca.crt) en el volumen Docker" "Warning"
                Show-Message "   Para eliminar errores de certificado, instale manualmente la CA:" "Warning"
                Show-Message "   pwsh -File init-certs-install.ps1 -CertName ca.crt" "Warning"
            }
        } else {
            Show-Message "❌ Falló la instalación del certificado PFX" "Error"
            exit 1
        }
    } elseif ($extension -eq ".crt") {
        # Instalar CA
        Show-Message "Instalando certificado de Autoridad Certificadora (CA)" "Header"
        $caFriendlyName = "ICBanking CA"
        Remove-ExistingCertificates -FriendlyName $caFriendlyName
        $certificateObject = [PSCustomObject]@{
            Name = [System.IO.Path]::GetFileName($CertPath)
            Path = $CertPath
            FriendlyName = $caFriendlyName
            Password = $null
            Subject = "CA"
            NotAfter = $null
        }
        Install-Certificates -Certificates @($certificateObject)
        Show-Message "Instalación Completa" "Header"
        Show-Message "✅ Proceso de instalación de certificado CA completado exitosamente"
    } else {
        Show-Message "❌ El archivo debe ser un certificado PFX (.pfx) o CA (.crt)" "Error"
        exit 1
    }

    Show-Message "Para verificar la instalación, ejecute: pwsh -File init-certs-install.ps1 -ListOnly"
    Show-Message "Para instalar un certificado específico por nombre de archivo: pwsh -File init-certs-install.ps1 -CertName <nombre-certificado>"
    Show-Message "Para instalar con contraseña específica: pwsh -File init-certs-install.ps1 -CertName <nombre-certificado> -CertPass <contraseña>"
    
} catch {
    Show-Message "❌ Error: $($_.Exception.Message)" "Error"
    exit 1
}
