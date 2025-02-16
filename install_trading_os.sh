#!/bin/bash
# Script di installazione automatica per Arch Linux - Trading Bot Optimized

### CONFIGURAZIONE ###
DRIVE="/dev/nvme0n1"
HOSTNAME="trading-station"
USERNAME="trader"
GPU_POWER_LIMIT="280" # Watt per RTX 2080 Ti
PYTHON_LIBS="numpy pandas ccxt ta-lib torch torchvision"

### PARTIZIONAMENTO ###
echo "1. Configurazione disco GPT..."
parted -s $DRIVE mklabel gpt
parted -s $DRIVE mkpart primary fat32 1MiB 513MiB
parted -s $DRIVE set 1 esp on
parted -s $DRIVE mkpart primary linux-swap 513MiB 16.5GiB
parted -s $DRIVE mkpart primary 16.5GiB 116.5GiB    # Root 100GB
parted -s $DRIVE mkpart primary 116.5GiB 316.5GiB   # Trading Data 200GB 
parted -s $DRIVE mkpart primary 316.5GiB 100%       # Home

### FORMATTAZIONE ###
echo "2. Formattazione partizioni..."
mkfs.fat -F32 -n EFI ${DRIVE}p1
mkswap -L SWAP ${DRIVE}p2
mkfs.btrfs -f -L ROOT ${DRIVE}p3
mkfs.xfs -L TRADING ${DRIVE}p4
mkfs.btrfs -f -L HOME ${DRIVE}p5

### MONTAGGIO ###
echo "3. Montaggio partizioni..."
mount -o compress=zstd:1,ssd,noatime ${DRIVE}p3 /mnt
mkdir -p /mnt/{boot,home,var/trading}
mount ${DRIVE}p1 /mnt/boot
swapon ${DRIVE}p2
mount -o compress=zstd:1,ssd,noatime ${DRIVE}p5 /mnt/home
mount -o noatime,logbsize=256k ${DRIVE}p4 /mnt/var/trading

### INSTALLAZIONE BASE ###
echo "4. Installazione sistema base..."
pacstrap /mnt base linux-rt linux-rt-headers linux-firmware \
btrfs-progs xfsprogs networkmanager nano sudo grub efibootmgr \
amd-ucode nvidia-dkms nvidia-utils cuda base-devel python python-pip git

### CONFIGURAZIONE SISTEMA ###
echo "5. Configurazione base..."
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash << EOF
echo "6. Configurazione nel chroot..."
timedatectl set-ntp true
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

echo "$HOSTNAME" > /etc/hostname
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

### UTENTE E SICUREZZA ###
useradd -m -G wheel,storage,power -s /bin/bash $USERNAME
echo "Imposta password per $USERNAME:"
passwd $USERNAME
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

### KERNEL RT E GRUB ###
sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="isolcpus=4-7,12-15 mitigations=off nohz_full=4-7,12-15 rcu_nocbs=4-7,12-15"/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

### NVIDIA E POWER ###
nvidia-xconfig --cool-bits=31 --enable-all-gpus
nvidia-smi -pm 1
nvidia-smi -pl $GPU_POWER_LIMIT
systemctl enable NetworkManager

### AMBIENTE PYTHON ###
sudo -u $USERNAME bash << USEREOF
mkdir -p /home/$USERNAME/trading-bot
python -m venv /home/$USERNAME/trading-bot/venv
source /home/$USERNAME/trading-bot/venv/bin/activate
pip install $PYTHON_LIBS --extra-index-url https://download.pytorch.org/whl/cu118
USEREOF
EOF

echo "7. Configurazione finale..."
cat << FINAL
INSTALLAZIONE COMPLETATA!
Comandi post-installazione:
1. reboot
2. Accedi come $USERNAME
3. Configura il bot in ~/trading-bot
4. Avvia servizio: sudo systemctl start trading-bot
FINAL
