#!/bin/bash
# Automatic Arch Linux Installer - Trading Bot Optimized
# Compatibile con UEFI/GPT e NVMe
# By Assistant - Modificato per Ryzen 2700X + RTX 2080 Ti

### CONFIGURAZIONE UTENTE ###
DRIVE="/dev/nvme0n1"         # Modifica con il tuo disco
HOSTNAME="trading-station"   # Nome del PC
USERNAME="trader"            # Nome utente
GPU_POWER="280"              # Limite potenza GPU (Watt)
PYTHON_LIBS="numpy pandas ccxt ta-lib torch torchvision" # Librerie Python

### FUNZIONE DI PULIZIA ###
cleanup() {
    echo "Pulizia partizioni..."
    umount -R /mnt 2>/dev/null
    swapoff ${DRIVE}p2 2>/dev/null
}

### PARTIZIONAMENTO AUTOMATICO ###
partition_disk() {
    echo "Creazione tabella partizioni GPT..."
    parted -s $DRIVE mklabel gpt
    parted -s $DRIVE mkpart primary fat32 1MiB 513MiB
    parted -s $DRIVE set 1 esp on
    parted -s $DRIVE mkpart primary linux-swap 513MiB 16.5GiB
    parted -s $DRIVE mkpart primary 16.5GiB 116.5GiB    # Root 100GB
    parted -s $DRIVE mkpart primary 116.5GiB 316.5GiB   # Trading Data 200GB
    parted -s $DRIVE mkpart primary 316.5GiB 100%       # Home
}

### FORMATTAZIONE ###
format_partitions() {
    echo "Formattazione partizioni..."
    mkfs.fat -F32 -n EFI ${DRIVE}p1
    mkswap -L SWAP ${DRIVE}p2
    mkfs.btrfs -f -L ROOT ${DRIVE}p3
    mkfs.xfs -L TRADING ${DRIVE}p4
    mkfs.btrfs -f -L HOME ${DRIVE}p5
}

### MONTAGGIO ###
mount_partitions() {
    echo "Montaggio filesystem..."
    mount -o compress=zstd:1,ssd,noatime ${DRIVE}p3 /mnt
    mkdir -p /mnt/{boot,home,var/trading}
    mount ${DRIVE}p1 /mnt/boot
    swapon ${DRIVE}p2
    mount -o compress=zstd:1,ssd,noatime ${DRIVE}p5 /mnt/home
    mount -o noatime,logbsize=256k ${DRIVE}p4 /mnt/var/trading
}

### INSTALLAZIONE PACCHETTI ###
install_base() {
    echo "Installazione sistema base..."
    pacstrap /mnt base linux-rt linux-rt-headers linux-firmware \
    btrfs-progs xfsprogs networkmanager nano sudo grub efibootmgr \
    amd-ucode nvidia-dkms nvidia-utils cuda base-devel python python-pip git
}

### CONFIGURAZIONE CHROOT ###
configure_system() {
    echo "Configurazione nel chroot..."
    genfstab -U /mnt >> /mnt/etc/fstab

    arch-chroot /mnt /bin/bash << EOF
    # Impostazioni base
    timedatectl set-ntp true
    ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
    hwclock --systohc

    # Localizzazione
    echo "$HOSTNAME" > /etc/hostname
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # Utente e sudo
    useradd -m -G wheel,storage,power -s /bin/bash $USERNAME
    echo "Imposta password per $USERNAME:"
    passwd $USERNAME
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

    # Configurazione GRUB
    sed -i 's|GRUB_CMDLINE_LINUX=""|GRUB_CMDLINE_LINUX="isolcpus=4-7,12-15 mitigations=off nohz_full=4-7,12-15 rcu_nocbs=4-7,12-15"|' /etc/default/grub
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg

    # Ottimizzazioni NVIDIA
    nvidia-xconfig --cool-bits=31 --enable-all-gpus
    nvidia-smi -pm 1
    nvidia-smi -pl $GPU_POWER
    systemctl enable NetworkManager

    # Ambiente Python
    sudo -u $USERNAME bash << USEREOF
    mkdir -p /home/$USERNAME/trading-bot
    python -m venv /home/$USERNAME/trading-bot/venv
    source /home/$USERNAME/trading-bot/venv/bin/activate
    pip install $PYTHON_LIBS --extra-index-url https://download.pytorch.org/whl/cu118
USEREOF
EOF
}

### MAIN ###
trap cleanup EXIT
partition_disk
format_partitions
mount_partitions
install_base
configure_system

echo "Installazione completata! Comandi post-installazione:"
echo "1. reboot"
echo "2. Accedi come $USERNAME"
echo "3. Configura il bot in ~/trading-bot"
echo "4. Avvia servizio: sudo systemctl start trading-bot"
