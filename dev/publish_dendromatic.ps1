# One-shot publish of dendromatic after `gh auth login`.
# 1. public repo <login>/dendromatic + push
# 2. seed gh-pages branch + enable GitHub Pages (pkgdown workflow deploys there)
# 3. r-universe registry repo <login>.r-universe.dev + push (dev/packages.json)
# Rerunnable: each step tolerates already-existing state.
$ErrorActionPreference = "Stop"
$gh  = "C:\Program Files\GitHub CLI\gh.exe"
$pkg = "G:\My Drive\3. PhD\08_software\dendromatic_pkg"

& $gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw "gh not authenticated - run: gh auth login --web" }
$login = (& $gh api user --jq .login).Trim()
Write-Output "Authenticated as: $login"

# --- 1. package repo ---------------------------------------------------------
& $gh repo view "$login/dendromatic" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  & $gh repo create "$login/dendromatic" --public --description "Processing, cleaning and normalization of dendrometer time series - the DendroMatic computational core"
}
git -C $pkg remote remove origin 2>$null
git -C $pkg remote add origin "https://github.com/$login/dendromatic.git"
git -C $pkg push -u origin master

# --- 2. Pages ----------------------------------------------------------------
$tmp = Join-Path $env:TEMP "ghpages_seed"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
git clone -q --no-checkout "https://github.com/$login/dendromatic.git" $tmp
git -C $tmp checkout -q --orphan gh-pages
"pkgdown site is deployed here by .github/workflows/pkgdown.yaml" |
  Out-File -Encoding ascii (Join-Path $tmp "index.html")
git -C $tmp add index.html
git -C $tmp -c user.name="Joao Gabriel Leal Martins" -c user.email="joaogabriellealmartins@gmail.com" commit -q -m "seed gh-pages"
git -C $tmp push origin gh-pages
try {
  & $gh api -X POST "repos/$login/dendromatic/pages" -f "source[branch]=gh-pages" -f "source[path]=/" 2>$null | Out-Null
} catch { Write-Output "Pages already enabled (or enable manually in repo Settings > Pages)." }

# --- 3. r-universe registry --------------------------------------------------
$uni = Join-Path $env:TEMP "runiverse_seed"
Remove-Item $uni -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $uni | Out-Null
Copy-Item (Join-Path $pkg "dev\packages.json") (Join-Path $uni "packages.json")
git -C $uni init -q
git -C $uni add packages.json
git -C $uni -c user.name="Joao Gabriel Leal Martins" -c user.email="joaogabriellealmartins@gmail.com" commit -q -m "register dendromatic + treenetproc"
& $gh repo view "$login/$login.r-universe.dev" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  & $gh repo create "$login/$login.r-universe.dev" --public --description "r-universe registry"
}
git -C $uni remote add origin "https://github.com/$login/$login.r-universe.dev.git"
git -C $uni branch -M main
git -C $uni push -u origin main

Write-Output ""
Write-Output "DONE. Remaining single browser step:"
Write-Output "  install the r-universe GitHub app -> https://github.com/apps/r-universe/installations/new"
Write-Output "Then the universe builds at https://$login.r-universe.dev within ~an hour."
