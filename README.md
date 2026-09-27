<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/icon-dark.png">
    <img src="docs/icon-light.png" width="96" alt="Clip.md icon: a clipboard with .md over it">
  </picture>
</p>

<h1 align="center">Clip.md</h1>

<p align="center">Clip.md watches the clipboard for apps you select to make sure that formatted text correctly pastes as Markdown when pasting into a code editor.</p>

---

To watch an app, open the menubar menu while that app is in front and pick **Watch &lt;App&gt;**. Click a watched app to stop watching it. Other clipboard formats (HTML, RTF, and so on) are left untouched.

## Install

Download `Clip.md.zip` from the [latest release](../../releases/latest), unzip it, and move it to `/Applications`. Releases are signed with Developer ID and notarized by Apple.

## Develop

```sh
mise run install     # build, copy to /Applications, launch
mise run test        # fixtures/* must convert to their .md siblings
mise run icon        # re-render docs/icon-*.png
mise run testflight  # sign for the Mac App Store and upload to TestFlight
mise run bump patch  # on main, CI releases a notarized v<VERSION> and uploads it to TestFlight
```
