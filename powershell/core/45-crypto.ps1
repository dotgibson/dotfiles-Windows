# ============================================================================
#  core/45-crypto.ps1  -  age encryption + croc file-transfer helpers
#
#  age  — modern, simple file encryption (https://age-encryption.org)
#           key lives at ~/.age/key.txt  (generate once with: age-keygen)
#           pairs with 1Password: store the private key in a secure note,
#           pull it back with: opsecret 'Personal/age/private-key' > ~/.age/key.txt
#
#  croc — peer-to-peer encrypted file transfer (https://github.com/schollz/croc)
#           send:    croc send <file>     (prints a code; share it with recipient)
#           receive: croc <code>          (or use `recv <code>` below)
#
#  Both sections are no-ops if the tool isn't installed.
# ============================================================================

# ============================================================================
#  age helpers
# ============================================================================
if (Test-Cmd age) {

    $script:AgeKey = Join-Path $HOME '.age\key.txt'
    $script:AgePubKey = $null

    # age-setup: generate a new key at the default location (idempotent)
    function age-setup {
        $dir = Split-Path $script:AgeKey -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if (Test-Path $script:AgeKey) {
            Write-Host "key already exists at $script:AgeKey" -ForegroundColor DarkYellow
            Write-Host "  public key: $(age-keygen -y $script:AgeKey)" -ForegroundColor DarkGray
            return
        }
        age-keygen -o $script:AgeKey
        Write-Host "key written to $script:AgeKey" -ForegroundColor Green
        Write-Host "  back it up in 1Password (create a 'Password'/'Secure Note' item, paste the file), e.g.:" -ForegroundColor DarkGray
        Write-Host "    op item create --category 'Secure Note' --title 'age private key' notesPlain=`"`$(Get-Content $script:AgeKey -Raw)`"" -ForegroundColor DarkGray
        Write-Host "  retrieve later with: opsecret 'Personal/age private key/notesPlain' > $script:AgeKey" -ForegroundColor DarkGray
    }

    # age-pubkey: show the public key for the default key (share this, not the key file)
    function age-pubkey {
        if (-not (Test-Path $script:AgeKey)) {
            Write-Error "no key at $script:AgeKey — run age-setup to create one"; return
        }
        age-keygen -y $script:AgeKey
    }

    # age-enc <file> [output]: encrypt a file to yourself using your public key.
    #   age-enc secrets.txt             -> secrets.txt.age
    #   age-enc secrets.txt vault.age   -> vault.age
    function age-enc {
        param(
            [Parameter(Mandatory)][string]$File,
            [string]$Out
        )
        if (-not (Test-Path $File))           { Write-Error "file not found: $File"; return }
        if (-not (Test-Path $script:AgeKey))  { Write-Error "no key at $script:AgeKey — run age-setup"; return }
        if (-not $script:AgePubKey) { $script:AgePubKey = age-keygen -y $script:AgeKey 2>$null }
        $pub = $script:AgePubKey
        if (-not $Out) { $Out = "$File.age" }
        age -r $pub -o $Out $File
        if ($LASTEXITCODE -eq 0) { Write-Host "encrypted -> $Out" -ForegroundColor Green }
    }

    # age-dec <file.age> [output]: decrypt a file encrypted with your key.
    #   age-dec secrets.txt.age         -> secrets.txt  (strips .age suffix)
    #   age-dec vault.age plain.txt     -> plain.txt
    function age-dec {
        param(
            [Parameter(Mandatory)][string]$File,
            [string]$Out
        )
        if (-not (Test-Path $File))           { Write-Error "file not found: $File"; return }
        if (-not (Test-Path $script:AgeKey))  { Write-Error "no key at $script:AgeKey — run age-setup"; return }
        if (-not $Out) { $Out = $File -replace '\.age$', '' }
        age -d -i $script:AgeKey -o $Out $File
        if ($LASTEXITCODE -eq 0) { Write-Host "decrypted -> $Out" -ForegroundColor Green }
    }

    # age-enc-pw <file> [output]: password-based encryption (no key file needed).
    # Useful for one-off files shared with someone who doesn't have your public key.
    function age-enc-pw {
        param(
            [Parameter(Mandatory)][string]$File,
            [string]$Out
        )
        if (-not (Test-Path $File)) { Write-Error "file not found: $File"; return }
        if (-not $Out) { $Out = "$File.age" }
        age -p -o $Out $File
        if ($LASTEXITCODE -eq 0) { Write-Host "encrypted (passphrase) -> $Out" -ForegroundColor Green }
    }

}

# ============================================================================
#  croc helpers
# ============================================================================
if (Test-Cmd croc) {

    # send: shorthand for `croc send`. Accepts files, dirs, or multiple targets.
    #   send report.pdf
    #   send dist/ logs/ notes.txt
    function send {
        croc send @args
    }

    # recv: receive a croc transfer by code. The code is printed by the sender.
    #   recv 5-right-today
    function recv {
        croc @args
    }

}
