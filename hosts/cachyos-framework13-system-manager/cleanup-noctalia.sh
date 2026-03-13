#!/usr/bin/env bash
set -euo pipefail

# Clean up the default Noctalia shell and CachyOS niri dotfiles that ship
# with a CachyOS niri install. Run this AFTER bootstrapping the Nix config
# so home-manager owns the niri/waybar/GTK configuration instead.

echo "==> Marking packages to keep as explicitly installed..."
sudo pacman -D --asexplicit --noconfirm \
  niri \
  xwayland-satellite \
  wl-clipboard \
  xdg-desktop-portal-gtk \
  2>/dev/null || true

echo "==> Removing cachyos-niri-noctalia and noctalia-shell..."
sudo pacman -Rns --noconfirm cachyos-niri-noctalia noctalia-shell 2>/dev/null || true

echo "==> Removing leftover Noctalia config files..."
rm -rf ~/.config/noctalia
rm -rf ~/.config/niri/cfg

echo "==> Removing skeleton GTK configs (home-manager will regenerate)..."
rm -f ~/.config/gtk-3.0/settings.ini
rm -f ~/.config/gtk-4.0/settings.ini

echo "==> Removing orphaned packages..."
orphans=$(pacman -Qdtq 2>/dev/null || true)
if [[ -n "$orphans" ]]; then
  echo "$orphans" | sudo pacman -Rns --noconfirm -
else
  echo "    No orphans found."
fi

echo "==> Noctalia cleanup complete."
