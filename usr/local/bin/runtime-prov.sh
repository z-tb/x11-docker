#!/bin/bash
set -e

# -----------------------------
# Entrypoint: ephemeral provisioning + user execution
# This user is removed after provisioning but has root access to the commands
# below via sudo. The sudoers file is removed after provisioning.
# for this reason, all commands requiring root privs must have sudo prefixed.
# -----------------------------
EPHEMERAL_USER=$(whoami)

# -----------------------------
# consisten output formatting
# -----------------------------
info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# -----------------------------
# Runtime provisioning: user info for runtime user. These should match host system so UID and GID match what gets  written to the volume mounts
# -----------------------------
USER_UID="${USER_UID:-1000}"
USER_GROUP_GID="${USER_GROUP_GID:-1000}"
USER_GROUP_NAME="${USER_GROUP_NAME:-user}"
USER_NAME="${USER_NAME:-user}"
USER_SHELL="${USER_SHELL:-/bin/bash}"
USER_HOME="${USER_HOME:-/home/$USER_NAME}"

# -----------------------------
# Ceate symlinks, report errors
# Add more symlinks below, if needed
# -----------------------------
symlink_status=0
create_symlink() {
    local src=$1
    local dest=$2
    local label=$3

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        warn "[SYMLINK] $label already exists: $dest"
    else
        if ln -s "$src" "$dest"; then
            success "[SYMLINK] $label created: $src → $dest"
        else
            warn "[SYMLINK] Failed to create $label: $src → $dest"
            symlink_status=1
        fi
    fi
}

# -----------------------------
# Runtime provisioning: startup
# -----------------------------
info "Starting /usr/local/bin/runtime-prov.sh"

# -----------------------------
# Create group. probably shouldn't exist yet
# -----------------------------
info "Creating user group $USER_GROUP_NAME"
if ! getent group "$USER_GROUP_NAME" >/dev/null; then
    if sudo groupadd -g "$USER_GROUP_GID" "$USER_GROUP_NAME"; then
        success "[GROUP] Created group $USER_GROUP_NAME (GID $USER_GROUP_GID)"
    else
        warn "[GROUP] Failed to create group $USER_GROUP_NAME"
    fi
else
    warn "[GROUP] Group $USER_GROUP_NAME already exists"
fi

# -----------------------------
# Create user from runtime UID/GID
# -----------------------------
info "Creating user account for $USER_NAME"
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    # Only use -m if home directory does not already exist
    USERADD_ARGS=("-u" "$USER_UID" "-g" "$USER_GROUP_GID" "-G" "sudo" "-d" "$USER_HOME" "-s" "$USER_SHELL")
    [ ! -d "$USER_HOME" ] && USERADD_ARGS+=("-m")

    if sudo useradd "${USERADD_ARGS[@]}" "$USER_NAME"; then
        echo "$USER_NAME ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/sudo-users >/dev/null
        success "[USER] Created user $USER_NAME (UID $USER_UID)"
    else
        warn "[USER] Failed to create user $USER_NAME"
    fi
else
    warn "[USER] User $USER_NAME already exists"
fi


# -----------------------------
# Setup home directories
# -----------------------------
info "Creating home subdirectories in $USER_HOME"
if mkdir -p "$USER_HOME/.config" "$USER_HOME/.local"; then
    success "[HOME] Created home subdirectories"
else
    warn "[HOME] Home subdirectories already exist"
fi

if chown -R "$USER_UID:$USER_GROUP_GID" "$USER_HOME"; then
    success "[HOME] Set ownership for $USER_HOME"
else
    warn "[HOME] Failed to set ownership for $USER_HOME"
fi

# -----------------------------
# Append custom bashrc additions
# -----------------------------
info "Checking for bashrc additions in $USER_HOME/.bashrc"
if ! grep -q 'pcol' "$USER_HOME/.bashrc" 2>/dev/null; then
    if echo 'pcol' >> "$USER_HOME/.bashrc"; then
        success "[BASHRC] Appended custom bashrc additions"
    else
        warn "[BASHRC] Failed to append custom bashrc additions"
    fi
else
    warn "[BASHRC] Custom bashrc additions already present"
fi

# -----------------------------
# Mount-based symlinks for user config
# -----------------------------
info "Creating symlinks for mounted home directories..."

# SSH symlink only if SSH agent not detected
if [ -z "$SSH_AUTH_SOCK" ]; then
    create_symlink "/mnt/home/${USER_NAME}/.ssh" "$USER_HOME/.ssh" "SSH directory"
else
    success "[SSH] SSH agent detected; skipping SSH symlink"
fi

# Other configs
create_symlink "/mnt/home/${USER_NAME}/.gitconfig"    "$USER_HOME/.gitconfig" "Git config"
create_symlink "/mnt/home/${USER_NAME}/.kiro"         "$USER_HOME/.kiro" "Kiro settings"
create_symlink "/mnt/home/${USER_NAME}/.config/Kiro"  "$USER_HOME/.config/Kiro" "Kiro config"
create_symlink "/mnt/home/${USER_NAME}/.config/pulse" "$USER_HOME/.config/pulse" "PulseAudio config"

# -----------------------------
# Symlink summary
# -----------------------------
if [ $symlink_status -eq 0 ]; then
    success "[SYMLINK] All symlinks created successfully"
else
    warn "[SYMLINK] Some symlinks failed (see messages above)"
fi

# -----------------------------
# SSH agent / key - prefer forwarded agent if available
# -----------------------------
info "Checking for SSH agent..."
if [ -z "$SSH_AUTH_SOCK" ]; then
    warn "[SSH] SSH agent not detected (SSH_AUTH_SOCK empty)"
    echo "   ssh-agent forwarding will not be enabled inside the container."
    echo "   Options:"
    echo "     1) Forward your host SSH agent:"
    echo "        docker run -it -v \$SSH_AUTH_SOCK:\$SSH_AUTH_SOCK -e SSH_AUTH_SOCK=\$SSH_AUTH_SOCK ..."
    echo "     2) Symlink your host SSH keys:"
    echo "        ln -s /mnt/home/${USER_NAME}/.ssh \$HOME/.ssh"
else
    success "[SSH] SSH agent detected via SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
fi

# -----------------------------
# Completion
# -----------------------------    

# remove the elevation privilege for the ephemeral user
info "Removing ephemeral user '$EPHEMERAL_USER' sudo privileges..."
rm -f /etc/sudoers.d/entrypoint && success "Ephemeral user privileges removed" || exit

# lock the ephemeral user account
info "Locking ephemeral user '$EPHEMERAL_USER' account..."
usermod -L "$EPHEMERAL_USER" && success "Ephemeral user locked" || exit 

# drop privs to runtime user and start shell
success "Runtime user provisioning complete. Starting shell for \033[1;33m${USER_NAME}\033[0m..."
exec sudo -u "$USER_NAME" -H bash
