$secure = Read-Host "Entrez votre nouveau mot de passe" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    if ($password.Length -lt 12 -or $password.Length -gt 64 -or $password -notmatch '^[\x20-\x7E]+$') {
        throw "Mot de passe invalide. Utilisez 12 a 64 caracteres ASCII."
    }

    $salt = New-Object byte[] 16
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($salt)

    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $password,
        $salt,
        100000,
        [Security.Cryptography.HashAlgorithmName]::SHA256
    )

    $hash = $derive.GetBytes(32)

    Write-Output "SALT=$([BitConverter]::ToString($salt).Replace('-', '').ToLower())"
    Write-Output "HASH=$([BitConverter]::ToString($hash).Replace('-', '').ToLower())"

    $derive.Dispose()
    $rng.Dispose()
}
finally {
    $password = $null
    Remove-Variable secure -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}