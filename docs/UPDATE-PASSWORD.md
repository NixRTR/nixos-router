# How to Update the System User Password

The system user password is stored as a **hashed password** in `secrets/secrets.yaml` for security and reliability.

---

## 🔐 Initial Setup / Changing Password

### Step 1: Generate a Hashed Password

On any Linux system (including WSL):

```bash
# Generate SHA-512 hashed password
mkpasswd -m sha-512

# You'll be prompted to enter your password twice
# Output will look like:
# $6$rounds=5000$saltsaltsal$hashhashhashhash...
```

**Alternative methods:**

```bash
# Using Python (if mkpasswd not available)
python3 -c 'import crypt; print(crypt.crypt("your-password-here", crypt.mksalt(crypt.METHOD_SHA512)))'

# Using Perl
perl -e 'print crypt("your-password-here", "\$6\$saltsaltsalt") . "\n"'

# Using openssl
openssl passwd -6
```

**Copy the entire hash** (starts with `$6$...`)

---

### Step 2: Update secrets.yaml

On your router (or wherever you manage secrets):

```bash
cd /etc/nixos
sops secrets/secrets.yaml
```

This opens the encrypted file in your editor.

**Update or add the password-hash entry:**

```yaml
# OLD (remove this if it exists):
password: your-plaintext-password

# NEW (use the hash from Step 1):
password-hash: $6$rounds=5000$saltsaltsal$hashhashhashhash...

# Other secrets remain unchanged:
pppoe-username: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
pppoe-password: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
linode-api-token: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
```

**Save and exit** - sops will automatically encrypt the new value.

---

### Step 3: Apply Changes

```bash
# Rebuild the system
sudo nixos-rebuild switch

# The password will be applied immediately
# You can now login with the new password
```

---

## 🔍 Verification

Test the new password:

```bash
# From another terminal or SSH session
su - routeradmin
# Enter the new password

# Or test SSH (if configured)
ssh routeradmin@router-ip
```

**Important:** Don't close your current session until you've verified the new password works!

---

## 📋 Full Example

```bash
# 1. Generate hash
$ mkpasswd -m sha-512
Password: [enter: MyNewPassword123!]
$6$rounds=5000$abcdefghijkl$XYZ123...longhashere

# 2. Edit secrets
$ cd /etc/nixos
$ sops secrets/secrets.yaml

# In the editor, update:
password-hash: $6$rounds=5000$abcdefghijkl$XYZ123...longhashere

# Save and exit

# 3. Apply
$ sudo nixos-rebuild switch

# 4. Test (in new terminal)
$ su - routeradmin
Password: MyNewPassword123!
[routeradmin@nixos-router:~]$  ✓ Success!
```

---

## 🔧 Troubleshooting

### "Permission denied" when trying to login

**Option 1: Use SSH keys**
- SSH keys (configured in `router-config.nix`) will still work
- Login via SSH and fix the password

**Option 2: Use auto-login console**
- Physical console auto-logs in as the router user
- Run: `sudo sops secrets/secrets.yaml` and fix the password-hash
- Run: `sudo nixos-rebuild switch`

**Option 3: Boot into rescue mode**
- Boot from NixOS ISO
- Mount the system
- Fix `/etc/nixos/secrets/secrets.yaml`

### Hash doesn't look right

A valid SHA-512 hash looks like:
```
$6$rounds=5000$saltsaltsal$hashhashhashhash...
```

- Must start with `$6$`
- Usually 100+ characters long
- Contains only alphanumeric characters, `/`, `$`, and `.`

### Password doesn't work after rebuild

Check sops logs:
```bash
sudo journalctl -u sops-nix -n 50

# Look for errors about password-hash secret
```

Check the secret exists:
```bash
sudo ls -la /run/secrets/password-hash
# Should exist and be readable by root
```

---

## 🔄 Emergency Password Reset

If locked out and can't access the system:

### Method 1: Boot from ISO

1. Boot from NixOS installation ISO
2. Mount the system:
   ```bash
   sudo mount /dev/disk/by-label/nixos /mnt
   cd /mnt/etc/nixos
   ```
3. Generate new hash:
   ```bash
   mkpasswd -m sha-512
   ```
4. Edit secrets:
   ```bash
   sops secrets/secrets.yaml
   # Update password-hash
   ```
5. Reboot

### Method 2: Use Installation Scripts

If you have the USB installer with `router-config.nix`:

1. Boot from installer
2. Run update script:
   ```bash
   curl -sSL https://beard.click/nixos-router-config | bash
   ```
3. This will regenerate secrets with new password

---

## 💡 Best Practices

✅ **Use strong passwords**: 12+ characters, mixed case, numbers, symbols  
✅ **Test before closing session**: Always verify new password works  
✅ **Keep SSH keys**: Configure SSH keys as backup authentication  
✅ **Store hash securely**: The hash itself is not reversible, but keep secrets.yaml secure  
✅ **Regular updates**: Change password periodically  

---

## 📖 Technical Details

### Why Hashed Passwords?

**Previous approach** (plaintext in secrets):
- ❌ Timing issues with activation scripts
- ❌ Password temporarily exists as plaintext on disk
- ❌ Race conditions with sops

**Current approach** (hashed in secrets):
- ✅ Native NixOS `hashedPasswordFile` support
- ✅ Password never exists as plaintext on router
- ✅ No timing issues - works perfectly with sops
- ✅ Atomic updates on rebuild

### How It Works

```
┌──────────────────────────┐
│  secrets.yaml            │
│  password-hash: $6$...   │
└────────────┬─────────────┘
             │ sops decrypt
             ▼
┌──────────────────────────┐
│  /run/secrets/           │
│    password-hash         │
└────────────┬─────────────┘
             │ NixOS reads
             ▼
┌──────────────────────────┐
│  /etc/shadow             │
│  routeradmin:$6$...:...  │
└──────────────────────────┘
```

---

**Last Updated**: November 14, 2025  
**Applies to**: NixOS Router v2.0+ with sops-nix

