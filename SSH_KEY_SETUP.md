# SSH Key Setup for GitHub Actions

## Problem
GitHub Actions cannot use password-protected SSH keys because there's no way to enter the password during automated workflows. You need either a passwordless SSH key or to create a new one specifically for GitHub Actions.

## Option 1: Create a New SSH Key (Recommended)

### Step 1: Open WSL
```bash
wsl
```

### Step 2: Generate a new SSH key WITHOUT password
```bash
# Create a new key specifically for GitHub Actions (no passphrase)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/wpi_github_actions -N ""
```
**IMPORTANT**: When prompted for a passphrase, just press Enter (leave it empty)

### Step 3: Add the public key to WPI VM
```bash
# Display the public key
cat ~/.ssh/wpi_github_actions.pub

# Copy the output, then SSH to VM and add it
ssh -p 2222 your-username@melnibone.wpi.edu

# Once connected to VM, add the key
echo "paste-your-public-key-here" >> ~/.ssh/authorized_keys
exit
```

### Step 4: Test the new key
```bash
# Test connection with the new key
ssh -i ~/.ssh/wpi_github_actions -p 2222 your-username@melnibone.wpi.edu "echo 'New key works!'"
```

### Step 5: Export the private key for GitHub
```bash
# Display the private key
cat ~/.ssh/wpi_github_actions

# Copy EVERYTHING including:
# -----BEGIN RSA PRIVATE KEY-----
# ... key content ...
# -----END RSA PRIVATE KEY-----
```

### Step 6: Add to GitHub Secrets
1. Go to: https://github.com/Sonica-B/Case-Studies/settings/secrets/actions
2. Create new secret:
   - Name: `WPI_SSH_KEY`
   - Value: Paste the entire private key from Step 5

---

## Option 2: Export Existing Key from WSL

### If your existing key doesn't have a password:

#### Step 1: Access WSL and get your key
```bash
wsl
cat ~/.ssh/id_rsa
```

#### Step 2: Copy to Windows clipboard
```bash
# Option A: If you have Windows Terminal
cat ~/.ssh/id_rsa | clip.exe

# Option B: Manual copy
cat ~/.ssh/id_rsa
# Then manually select and copy all text
```

### If your existing key HAS a password:
**You cannot use this key with GitHub Actions.** You must create a new passwordless key (see Option 1).

---

## Option 3: Create Key from Windows (PowerShell)

If you prefer not to use WSL:

### Step 1: Open PowerShell as Administrator
```powershell
# Generate new SSH key (no password)
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\wpi_github_actions" -N '""'
```

### Step 2: Display the public key
```powershell
Get-Content "$env:USERPROFILE\.ssh\wpi_github_actions.pub"
```

### Step 3: Add public key to WPI VM
```powershell
# SSH to VM
ssh -p 2222 your-username@melnibone.wpi.edu

# Add the public key (paste from Step 2)
echo "your-public-key-here" >> ~/.ssh/authorized_keys
exit
```

### Step 4: Get private key for GitHub
```powershell
Get-Content "$env:USERPROFILE\.ssh\wpi_github_actions"
```

---

## Quick WSL Key Export Script

Save this as `export_key.sh` in WSL:

```bash
#!/bin/bash
# Quick script to export SSH key from WSL

KEY_FILE="$1"
if [ -z "$KEY_FILE" ]; then
    KEY_FILE="$HOME/.ssh/id_rsa"
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "Error: Key file not found: $KEY_FILE"
    exit 1
fi

echo "========================================="
echo "SSH Private Key for GitHub Secrets"
echo "========================================="
echo
cat "$KEY_FILE"
echo
echo "========================================="
echo "Copy everything between the lines above"
echo "including BEGIN and END lines"
echo "========================================="

# Optional: Copy to Windows clipboard
if command -v clip.exe &> /dev/null; then
    cat "$KEY_FILE" | clip.exe
    echo
    echo "✅ Key copied to Windows clipboard!"
fi
```

Usage:
```bash
# For default key
./export_key.sh

# For specific key
./export_key.sh ~/.ssh/wpi_github_actions
```

---

## Verification

After adding the key to GitHub Secrets, verify it works:

### Test locally first:
```bash
# From WSL or Windows
ssh -i path/to/your/key -p 2222 your-username@melnibone.wpi.edu "echo 'Key works!'"
```

### Then test GitHub Actions:
1. Go to Actions tab
2. Run any workflow (e.g., "Deploy to Remote WPI VM")
3. Check if SSH connection succeeds

---

## Security Notes

### For passwordless keys:
- **Only use for GitHub Actions** - Don't use for personal SSH access
- **Keep private** - Never commit to repository
- **Rotate regularly** - Create new keys periodically
- **Limit scope** - Only add to specific VMs that need automation

### Best practice setup:
```
~/.ssh/
├── id_rsa              # Personal key (with password)
├── id_rsa.pub          # Personal public key
├── wpi_github_actions  # GitHub Actions key (no password)
└── wpi_github_actions.pub  # GitHub Actions public key
```

### SSH Config (optional):
Add to `~/.ssh/config` in WSL:
```
Host wpi-vm
    HostName melnibone.wpi.edu
    Port 2222
    User your-username
    IdentityFile ~/.ssh/id_rsa

Host wpi-vm-auto
    HostName melnibone.wpi.edu
    Port 2222
    User your-username
    IdentityFile ~/.ssh/wpi_github_actions
```

Then you can use:
```bash
ssh wpi-vm          # Uses personal key (with password)
ssh wpi-vm-auto     # Uses automation key (no password)
```

---

## Troubleshooting

### "Permission denied (publickey)"
- Public key not added to VM's `~/.ssh/authorized_keys`
- Wrong private key in GitHub secret
- Key has incorrect permissions (should be 600)

### "Host key verification failed"
- First time connecting to VM
- Add `-o StrictHostKeyChecking=no` for automation

### "Bad owner or permissions"
```bash
# Fix permissions in WSL
chmod 700 ~/.ssh
chmod 600 ~/.ssh/wpi_github_actions
chmod 644 ~/.ssh/wpi_github_actions.pub
```

### Can't access key from WSL in Windows
```bash
# Copy from WSL to Windows
cp ~/.ssh/wpi_github_actions /mnt/c/Users/your-windows-username/Desktop/
```

---

## Next Steps

After setting up the passwordless SSH key:

1. ✅ Add `WPI_SSH_KEY` to GitHub Secrets
2. ✅ Add `WPI_USERNAME` to GitHub Secrets
3. ✅ Add `HF_TOKEN` to GitHub Secrets
4. ✅ Add `NGROK_AUTHTOKEN` to GitHub Secrets
5. ✅ Run "Deploy to Remote WPI VM" workflow

The deployment will now work automatically without any password prompts!