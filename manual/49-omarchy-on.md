# Omarchy on...

### Apple Silicon Macs

Omarchy for Apple Silicon runs on M1, M2 and M3 Macs and installs next to macOS. See [Omarchy for Apple Silicon](44-mac-support.md#omarchy-for-apple-silicon) in the Mac support chapter.

### Try Omarchy on a Mac

[Try Omarchy](https://github.com/omacom/try-omarchy) runs Omarchy in a virtual machine on any Apple Silicon Mac with macOS 15 or newer, with nothing to partition or install beside macOS.

### VirtualBox

VirtualBox is a popular VM runner. [You can run Omarchy inside that too](https://github.com/omacom/omarchy/discussions/176). But performance probably won't be great.

### VMware Workstation on Windows 11

Another popular VM runner for Windows. [Omarchy has been setup inside of that as well](https://github.com/omacom/omarchy/discussions/572).

### Steam Deck

The Steam Deck runs on Arch, which means you can run Omarchy on your Steam Deck. Altynbek Orumbayev has [a full setup script and explanation on how to do it](https://github.com/aorumbayev/deckarchy). How cool is that!

### ROG Ally (2023)

Omarchy recognises the original ASUS ROG Ally RC71L, including the Ryzen Z1 Extreme. The Ally X and Xbox Ally are separate models and are not covered by this setup. The RC71L remains an x86 machine; it does not need a separate platform or image.

The RC71L skips the ROG laptop asusctl installation and laptop audio mixer and microphone changes. This does not remove packages from an existing installation. Its tablet chassis already follows Omarchy's portable display handling. Display scale, refresh rate and orientation remain under your control in the display panel.

After networking is ready, first login offers optional gaming setup once. Dismissing the invitation does not install anything; Steam remains available under Install > Gaming. Its installer selects graphics drivers for the detected GPU. Steam offers Big Picture for a controller-oriented interface inside the desktop. This does not replace the desktop session or change idle and sleep settings.

Controller access through the kernel's xpad driver and touchscreen recognition have been checked on an RC71L. Game compatibility and advanced controls still need individual testing. No gyro, rear-button remapping, fan or TDP management daemon is installed by this hardware setup.

### NixOS

Omarchy is really Arch + Hyprland, but Henry Sipp has [ported the essence of the setup to NixOS](https://github.com/henrysipp/omarchy-nix). So if you've been nix-pilled, here's a good starting point. It may or may not stay up-to-date with the latest Omarchy changes, but it's pretty cool none the less!

### Something else!

If you're trying to get Omarchy running on a configuration that isn't the default, you should join the #omarchy-on-other channel on [our community Discord](https://discord.gg/tXFUdasqhY).
