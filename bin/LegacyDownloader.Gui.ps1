# LegacyDownloader.Gui.ps1 - the windowed interface (default front-end).
#
# Dot-sourced by LegacyDownloader.ps1 after the core module is imported,
# Initialize-LegacyCore has run and Initialize-Language has set the language.
# Relies on $Core being set by the entry script. The console front-end
# (LegacyDownloader.Console.ps1 / the -Console switch) is the fallback.

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $Core) {
    [System.Windows.Forms.MessageBox]::Show("Please run '..\LegacyDownloader-GUI.bat', not this file directly.") | Out-Null
    exit 1
}
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { }

# ---- state (everything touched from event handlers lives in script scope) ----
$script:ModPath   = Join-Path $Core.ScriptDir 'LegacyDownloader.Core.psm1'
$script:AppDir    = $Core.ScriptDir
$script:Conn      = $Core.Conn
$script:Cfg       = Load-Config
$script:Langs     = @(Get-AvailableLanguages)
$script:Busy      = $false
$script:Ready     = $false                # true once the main form is built (guards init-time events)
$script:ScanJob   = $null                 # background job running Get-UpdatePlan
$script:ScanOut   = $null                 # temp file the job writes the plan to (Export-Clixml)
$script:ScanIgnoredWrongLevel = $false
$script:Job       = $null                 # current Start-RcloneCopy handle
$script:CurrentSpec = $null               # the {Label;Source;Dest;Extra;Kind;Keep} queue entry $script:Job was started from
$script:Queue     = @()                   # remaining {Label;Source;Dest;Extra}
$script:LastObject = ''
$script:FirstRunMode  = $null             # 'get' / 'have' when the setup dialog just ran
$script:AutoRunDone   = $false            # one-shot guard for the first-run auto action

# Session-lifetime cache for Show-SongBrowserDialog's "songs on the share
# that aren't in the sheet" scan (edition -> codes, via Get-RemoteSongMap).
# Declared here, not inside that function, so it survives across separate
# dialog opens in the same running app instead of resetting to $null every
# time - without this the full share scan re-ran from scratch on every
# open, which was real repeated load on the share and the machine. See
# $script:SbRemoteMapCacheTtl's use in Show-SongBrowserDialog.
#
# 1 minute, not the original 5: that was sized around the scan taking one
# rclone.exe spawn PER EDITION (~24 of them, sequentially - measured at
# ~47s against the live share), where a long TTL was the only way to keep
# repeat dialog-opens cheap. Get-RemoteSongMap replaced that with one
# recursive listing (~4s measured against the same share, same results) -
# short enough that the cache no longer needs to trade "won't hammer the
# share" against "might sit on a stale scan and miss a just-added song for
# minutes" nearly as hard. 1 minute still absorbs someone opening/closing
# the picker repeatedly in quick succession, without risking a long stale
# window.
$script:SbRemoteMapCache     = $null
$script:SbRemoteMapCacheTime = $null
$script:SbRemoteMapCacheTtl  = New-TimeSpan -Minutes 1

# ---- embedded flag bitmaps (20x15 PNGs) ----
$script:FlagB64 = @{
    'de'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAABxUlEQVQ4ja3Ty24URxQA0FPVNWT8APwIEYoMgjVIZpdIUf4i4g/5APb5CUvsYY1lGxuPPY/uWyyqEZOJ2SBaurpd1apT91Z3p1LK3xFxjOf4LSK2kXLOq4j4jEucjXGOT5hhjowdPBrXH6eU0r94VWs9QHL3tRyxszVwMYLbI/gMuwn1O8gPXflnYlAyjvAUB7g3Pqi4xpXW48WY53cg09F4jPIP/tAOYH8E6xgz7Y2sg5e4wbCG7eN3rd30lvoS3Vpl63lzbjmC/TieYgsrvEPZWqvoLmAzT/BgY83X+0BZh9Iu6ZdWbl0wzFu+C94EQyu1dEdsv2B6RN5rYOqIBXFLXDFcMlzQXzFcEzNqbVCa0O2z9Zj725Td1+z9xfQJqfx/61gQnxo4XH4DRUPThLKPR+yeUqZ/MnnaqvpPL2PkCflXyuF3+hznlivqR0odB/MFfU8M1Gj/YE50uX2sXyNtHmIlgtt5W1dqcHruuu996AenQ++mMqimXbKTk73MYc4OuuReyW2jrLU8DCyX6uzW+RBOSq3enF04ifB+lZx2K7NIovamkezUsJc4iMEhDifFw8z9LplEqKvezWLp49B7X6uTL16L4e3tydldAAAAAElFTkSuQmCC'
    'en'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAMAAADTRh9nAAABgFBMVEUBG1SYl6efDSfKfooAG1cCLGy+n6UCIF0AE0YAGlSpL0LAlZynUmifDSeSkqLTiJjZ2dm7u7u2b3i/VG6vt8NGZJGUPUjFpq1AS2xRT3VeWoAAEkV5cImapbm6FDSjCh+mCSCflKR9hJa3EzMCKWmGeZLHDizJEjLCDCfkj5/afo7OIUEAF1TgeotTZpWpscjFvMwCK3DGGzXLFjjRPlbll6PliJrqp7Lonq2tuM9dcJkBIWTPL0rVW3HduMOjVHNhVH8qT4mwW3EWKmK7CyNGWYMxRXbLJkDt1Nvcc4P39/q8hZ/ck6DsydHIbYSGU3mWFSerqr6YhKWifJZ8T3Q7ToWZXmxfe6jBa4rayNTptb3Iz98VOXemnK5NUHW4tsuPmbHbipe5sMStpLfhhJO9fZFpWIbpqrWsGDdTW3a1bH+Ch6uPepXda33NT2GEg6bByNqvKkT77/IAET+HXoj67O7rusUoNFhtNkqMocKgbIHNw9IpR4Pcz9rV2eSdlqS0UDBzAAAAJnRSTlM1jXrzwaw9ta1CdaTTZ1XsbGzsvI2jvf6jvr6cVNT55/nUjeecVBCdCscAAAEnSURBVBjTHdADlsMAFADAX7trW1HjpE3T1LZtrG3j6vte5wgD+tnFJZ1Od6hS2+wmADAdmS2wMOOXG12Om2wfbGkNBsO6VfMHhabL3foIcWMBZRSlGwyP2DiE6Oem61WmBygqc7VC3snSJHChRsntfuz8oOj9aYA4G9DxPnjKmQxO4ZKEokk/nkwzd5U6XPpEr8OR8IoIkqKOnSMidVuEc0EQHA4BmUJ5HsOiRXjwUQTudFE3CCJ6EzyfEH11+Cxfyekc7s9hWFvCqexJ5foCYt8eViICQRbDfjsv7myPjjyB4vnC89WaMsYwJsa0iXC1/wYxdhQIRkhyEo0yZHzYchLhd+hprGsGo1a7t7M7JMmIp7QyvwwW8+Y0x25T728YjcZV1Zz+HwHdQPKkb2RfAAAAAElFTkSuQmCC'
    'es'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAACmUlEQVQ4y22Ty25jRRCGv2r3sR1fZpJ4MmRAkBkWLBAoiH0WiCUPxcMgJN6DBRuEyEgsAI2GEZpLHHzie+zTp+tnYTsJEd0qVau79P1VrSr77pNPzzz7qbs/C+6PDXXkWMZTFrMsn7j7SNjIlUtzjTMs3FkJBVDXPR9JeubSafQ6f7tn9kXD7JAQzAQKjivgiIyRQ6PK7qUsjLL5OEuLbL6WCCZ1DDvCeDpx70W5f91tRKIZutmG2Cwn4PJmNjvO0nHGcNvcSwKEGSDjChEpMvtPE52jiqJXY9HBRK4gr4y0CKS5sZ4GqpmRFlBfbwQFEKH50GkOalJvTXzyVcnJaaL3OFH0akIUo2GH+TDQfSC6rTVpHqimgWoWqJdGWhpyIUGIovkg0zzIFKkmvnc2ZnACMWwkyzIwfFXw+/MOH36W+PzLJf33EwDapaXbs219SvDqDwjYNsg3/u27J5QvjOnkI8r1Ga//eYT0X9gOtIPhoK0F+Z1Ah+XVCYtJg8niAPnHXPx5jHwreC92Z7t3zxDuK68iNA8S9fgN899+RGqh/wPpNqu7WcYb9bApa//4HU1bY3tj+ipJH5xg3Mvu7hfcgecEsZoGLp8XVJcNVtPAejHFVdDKNa0Clr+OeD1s0eo7Rdcp2qJo6waYK1hNjPJt4MUvhv3wTV+Pxi3WF4HVLOC1cLYt0XbinhO7ugHGthPbm7YXoq7gemJcXQR+/lvENz+18dDA3Uk4rlugLYUtDRsZgYCJ7SSBpE21ElniWiJ5JrrE2PM8u/+V4bJGS3dlzNpIXWAfMTB0aNC07UiyBWaJWtI1Kl2cR5e+n3k+z9hLzC9dWtQ1TqPRdvduNvYNDrMxcPdBhIeG9SUVQkrSMsEwu7800/m/wsXxL/gOJaYAAAAASUVORK5CYII='
    'fil'     = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAACwElEQVQ4jV2SzWtcVRjGf++dO5lOJ0njpGkRKzZYN0WI7lRwKYpb0bVr9/4PbgQXuomIq1qwKS1WaKkRIoK6URlb2lADKWrSJtOZZJr5uHPnnvdxcW8mQzi8vOfz9z7nOccufnj5zfWdwRLuiyg64+IkQRYpjFx+QJZ1kLdwWuBtPNvHrYdHCZ5GYDWCFnBfBC3Zlys/rN66b6+sNjr1Ti8YAlzgDgoQHNxTFNp4aOFhH/ceHoa4IuAksgWc86RPp+3OHysaVN9g7V6f67/u8Mu9dg6UJnKAEPIsz/vyYh2Q5fv6/xKXSlVefbHO0oUzLL1Q5Zu1Kld+2qI/CMVmgRtQAovyuagoxGFBB43AnVjxeUCU1eKtlxMunK1zrl5h+fuHNPeSI5WHVuiY+kOgO8iJAZQ9RslvkDVZPP0OH7//EvXpMp9f3WBzuzcB4BjQi7GPPY8lQdaG/auQ7aDKRWZnFvno3WlOlcp8dqnExnafhPgINg4feznlQ54d7hZAjWD0H3g/9wmoxMZ7s9skrd95sHvAflSlU6pyYBX6VmZEhOTUQsIzWZezoyeUu38XQB/CzNtACSs/h3cT9q7/zN6Vm7x+909eywIDi8fAXlQmJUKIWkiYy7rMhgPuh6QAls9hlQ8AI93q0rq8TPvb7xj+s4Vy46goZWE05DQq3qhoyvNIjqMcaFPPQylj8Nddml9do71yAx8MiiMUh4AJwNG8cB1FLE8RTr+xweNPv6Zz80c8hHH1AjOGqvh7AnyygFQoTNZ5eqfE9idf0L69RvBcOoAhIshDeebYVQ9BiTxXmD5qsX5tufvk1urDIJqZvI8pCDtheM3EHDAfibqZpiKBTYCDRIo0ILQdNeLBg3Dp0Y3bjZHCpmHNkULPZJ6VdMI8q7lHc5jXg9s8pvlYOoUxY1B2UCbvp9JuhjYVrPE/NV8thfosIwwAAAAASUVORK5CYII='
    'fr'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAAB2UlEQVQ4jY2SPW4TURRGz33z7DhxEJFHQZRkAShUdNCwAdgBPYugoqBlD6yCkhVkBaG0EmxMYsfxeO79KDz+i+yIJ13Nm+bofPd7ll9/fBPYOeFnwLMIHRFh79++nH/99OF2Pp//lTSQNACG7j66+vJtMv7x816tSFFH1xWnCjuT/Dw7fCalV7LUQxgmsKBz2KUsS9wdd6/cfShpUNf16MbSpErMwi0lFUeGnWK8GKk+zop4R+4AQAgkIDg4OKQsSyTh7m13f94M43YbIyEJQyQSIIaITMQCIiCC9b8AMDNyzuScWZ7j3KLGEICBJOaIkMiEN5AN4HL2HElIgdDijohm8trqAbAx3AlkCWQN1cowwBtAPPg+ZoiaTS1AIRGwabgERVPO/sg0kM3IQvh6h/6glP/Y4SZsZagdhku7RyIvI24bxj7g9rPZW8pmw1rP7shNf49GbiJuxV4Zet3AHOQgMZtOGI1GFEWxetg5Z8yssYot0L1i49nU0zEev8CvibhD+Gx62+n3+92U0klKqUwp9YqiaOec+T2944981WyFNMWHgS4y6Dvz2QXSJebXeEywFFFVncFg0JV0Yma9iCiBstVqPe2Pb5/cyFsBqhV3lXRVo0u5XfwD3Lj3FBPR3T4AAAAASUVORK5CYII='
    'it'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAAB40lEQVQ4jZWTvXLTQBRGv7u7/kkcJhlrwjBU5AnCQE3FC9CFt6GmoaSh5k1oKP0EofQk2DGOFWJL9/soVjI2iSHszB1pC505R1pZ+vD2FeGnEE8APqZhH6K9efqyev/i7Lqqqh+SJpImAKbuPrv4+KlcfPl6KzLQMXD4sZwnAk+Tw9+hF58rhiEggwSI6B/uoSgKuDvcfeXuU0mTuq5nc4vlSrakhRCi9o3hGMmezVZ+kCS+xl4XiAAggARk6A36KIoCkuDuXXd/0gwWvR4sRkiESQhmgISphAQSCEJrloHNHoCZIaWElBLaddDpog4BYpaQiEoCM9AzBA1wDSV2LZGQOyQ1Q7CZbEgCpt8gEaB2A6UMRQNk3nOdLN9Ibk3/AdyYbKcN4J1k/TUZDWQbTHhO9vuT/8NQdw09A7eSdxtSBPmHIe/7KFvJDzVs7QiyPTZq3mEL10OAGdTeayu5qgEnUHu+UljObzCbzRBjXB/slBLMLD9MQSDEbHdL30ieLxdwfkPllxBv4PLl1aI/Ho8HIYSjEEIRQhjGGLspJXwvS1x5lX9LEitRP+VTAqME4TPK5Qi1ncN5CdUlFMhy2Z9MJgNJR2Y2JFkAKDqdzuH4ev5oXlUdmlRTNyv6RS2dixr9AmYGJOT/Z+8EAAAAAElFTkSuQmCC'
    'ja'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAMAAADTRh9nAAAA5FBMVEXX19fQ0NDMzMzc3NzMzMzFxcXe3t7Pz8/h4eHMzMzl5eXb29va2trX19fZ2dnKysrLy8vGxsbAwMDAwMDZ2dne3t7Z2dnj4+Pi4uLX19fb29vT09Pe3t65ubn////7+/v6+vq9AC7x8PG7ACv+/f65ACm/ATPV1dW2ACfR0dH89/jv7+/29vbo6Ojbe5O+vr7GxsbKM1jqsb7s7Oz08vO7DzbBCTjPSWrDw8PBFj7stsTsusbgjaHX19fz8/O2AyrKysrt7e326OvOV3DNQGL9+vvtxc3EOlfNzc3aaojUboTg4ODg1fN6AAAAHnRSTlO1d6bUVDyuQfMz/bu+japwrqCNaWzEnOfUxOfs/r1uIjwUAAAA10lEQVQY01XQ15KCQBAF0CYJomLWTaIM44gIKEFds2PYNfz//8gAVmk/nltdfatBbpS0XE5rlbiyKEv5vCxyPBSUkCJEQ1dtfzQLAEVBucDGwTob+xA5EaIUbZ09DLqM8NK7eoGdxL0nrnxCiL8+JzjJcE6IYRiL5SviGTPTnGc4TJFRvz9lR3u/Keonk5n1jsEiJss6JuvjDO21v7N2/39vqNuBd/NWOMOLsx3RkI4idEi7YxSjIhRBg0/hS7mrruuqP98d4Dkx/o0ki/VyrcpXKtVaXXoAVAEniyY09XwAAAAASUVORK5CYII='
    'ko'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAMAAADTRh9nAAABNVBMVEXe3t7MzMzMzMzc3Nzd3d3S0tLIyMjMzMzFxcXc3NzV1dXX19fU1NTh4eHf39/Z2dnLy8vX19fa2trGxsbAwMDLy8ve3t7m5ubX19fl5eXT09PCwsK5ubnT09O7u7v////6+vv+/v77+/u9vb3CwsL29vbOMT3X19cAQptlZWXv7u/Q0NDt7e11dXWxsbGrq6uioqLx8vTg4ODw8PDl5eXGxsabm5u5ubn5+fm0tLRtbW6NjY3T09NpOGmZNFPppKkyPoUaP4/geYH88PHyzdA8bLGzx+H44OJahL3z8/Pr6+vKysra4/D56eqmM03IQ1LxyMqINVvRQEs/PX5oaGi/M0UjVqK/yd/bZ3CEpdDd5/IVU6XXV2FZWVmSrtSBgYFfX1/uvMDHx8fNzc1WVlfB0OZWVlaQJKoeAAAAH3RSTlPUM1Su/XJBpju8s7dB8+e9Z42gn42uxPnE7Hp6vexsd+Kq8QAAARNJREFUGNNFztdygkAAheGlKNh7erK7wiIQAUHEFntfTe+9mOT9HyGQyUzuznw35wfxUCbLcVw2s5Nm4yLDhNmQAFLbVDclndLNJNiIcLEISKxBiWDaMmoQFxvEps1mdUGWoFSElc9vGc/GMwyl1iuFaAmOfHxro/fh3bA3kq60CkQfAeqmU35SFOWihzzNgqgWIMTw9lpRTrqnx3yd/OO00z2/7HfO/AmRHCBpOg83/YGqDsYBNmRwWISW1kb3j6qqTkYls/yHnvYs2y/zyXxKPP+9IQXoGoYM8eprBestw/pFstCtOtVtgvx4o23jqgTWCZCKRmNbIMk7rmuaLr+/B4QQG2YYMcymd/M5oVDI5Q/EH+/7MZmhhNx7AAAAAElFTkSuQmCC'
    'nl'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAACnElEQVQ4jY2TzW5cRRSEv3OnZ+Z6xiNPbGIZJwHCA5CwQyDYsGCFxIo3Yc3DIMQjsEA8QdgYiQULEiuKosSOx2PPjz33dlexGNtJJCRypJbqqHWqVN114qdPvviSogdyuV/Zu2EGlqLIbcGzVjqTy0k4TrLKJPC0hBedNl827lS4DEW5bem+xYOkoh8HEQ87dLbBERhXgRDFRhUU0xR5ouicFGsqaaHorCpUVcHAqm5HxEdntJvJ0teD1KUbYBtLGOGqWvcGiV4J75VKe0WBCBQVBrCJMISZZJMkUeHXZNIVkbHXOGw6mAqTAAgcYGItiGltZJOMqff32Ly7T3e8RaSEbbBo5wva83Oa0ymrySnN6ZS8vHhLzDZR9xndu8Puzpi09+03fPz5Z4w+vEfv1pjodgHAIi+WtOczmtPp+kzPaKZn5MUSl4yBqt+n/942vTvvs5Fb0t3vv2P/04ektDbzf1VWDWW5xKUAUNU13c0hbdvy4tEjUrVRvxPRdXX6PTr93n/eSSLZXju0mS8bLleZXETdS2zUibrffSch28wWl6SnL854fPw3z48XTKZLLlYtbS7UvUTdT2xt9hmPara3NhiPNhgN+wwHPTpVAHCxanl1Mufx05f89vsfpF9+/ZOjWc2zlzNWTUZ6/YNY9FLFeFRza6tmvFkzGvQZDrpUEdjictVy/GrG4bMjDv/5i/jgqx/cHexiB3orh4KrWPBGRG6wrvF6Rmpp58/XwS65RSqoZFB5Y/jqfQiCuNmMG8FrNyo4N1hlTZhXs7mVD13KsVSWtgqmBg+Bsc1OOLaNeybAYNY7aRWsbJVmYusggX/Oq/kBUZ4gH0fWIldWVVyDh8ZjF23b3rG1A7GFGRHuIlvKSzkfUfQE6eBfZNwTNPI35mgAAAAASUVORK5CYII='
    'pt'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAACEUlEQVQ4jY3UT2uUVxTH8c/zzDPJNGNMnDBptAq1GApBVEpXFXHRZd3YfXHnvq+gr8IX4ELcu3bRhUVcSRRaAsW/YG3ixNiZyfy997qYh1FrHDxwuJd7D9/zO+dwb1b8WlyIMZ4VnZSsRnFBlOUxHx3uxfad694kWokWdgN76Ob0AznqaGacjJwtQgy/KZxLUgOZhEhMUR5oIjAM7CZaY/YS3cAgkecsVGhW+HqHQ0WK6UdVZCYWS0/kc1PgXGCt9GkIE4mVcv0XhVDepHeRFawv0Vyks8HCc+bbZtqoRBQfpCv3l05x5lHNUkFnhc7RqsbDtvnt2dB4EHC1xi+n+ebGss7ln4WN/3RGd8Uv247eJE+fBibkU2Dp3y7R77OW6nbXr3j+01WhWNQ7Rn91tsIPgWW3U+TeM7pHojB/2KB5wlxrrGjTO/45JYcSVqbYesXpBltfdXz3x035F/OGq6/F76nenq3uwKHsdPm7xe31N4Z/XfPDq5q9i7saL6k/+xyFB0z59ye8aAw9WNtzfquwdmug/pTKaDYwTUv+H3Cc+PMl24Ng+X5Q7ZHNmO7HCsdMexneNWQ8YLA/OSpKzz4B6nm/h/s6gieCHdG+KKAWB+r/sJyzktOoMFeYPLO8BAQMSd3Jx7FZiG7o2xQ9Fu0IuoKoUMt66tssZzQiK1ipspSzWKEaSSP2B2wHHic23wLmpgDwKBqqjgAAAABJRU5ErkJggg=='
    'ru'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAAClUlEQVQ4jW2Sy24jVRCGv3PpTsd2MrGTGYHECOYB0LBGgg0vwdvwGKxZ8AhIbFgiFrPKCiIEGWYWkDh2nKTtuC9VPws3c2NK+lXn6Jz66qIKZ2dnXwBPgScxxkc555G7B0mdmd11XXcjaSFpASzNbAWsY4xbM4vAGHgYQnji7k8z8M1kMvmsLMtZSinEGAFwd9wdM8PMWjNbSlr0fb+StDazRlKMMY5SSg9TSp/M5/NJdvevptMpVVURQuBdk4SZlWb2waBXyQBijKSUiDFycXFBlkRRFO+FAYQQyDmTc37v+3/WdR2SyO7iz3/WvJg3zFcNTecgCMDBfuZoUjA7LDk5LJkdloyq/4PX9z2//3XNjz+/JH/30wv+3tacX2yZX29pWgOHiDioMg/GBccHBceHJbODgumkZFwlUgoguN92XC7u+ePlNc+e/Ub+9ofn1KxBEdxBAh8kgXjjLMocGO8lcgQkNtuWdd2CeljfketNB5VA/jboXT+obUS77Xb/pdfeHeRk3IdLZGIbKmtJMhrP3JNpVOyCeBv8qoA3wPt+T37cXfFpuOSj/pqp3bHnLdmNrRIbCm5DxQ37LBlxS0XNHrVKpF3LpRqmVvOhXTFqfyV/vf2FL/tbHtuSwns0zFESEjQkVmHEkhE37FNTUrM3TEKU3jL1mke25LK7In/envExiSQhH8QOiKBQxwk3nGg1dCu023h8aF+C1p0LF9nd6QwaF50L8wHGbhejRAQSEAfQa/CuABdsfZcgy51Fp7p3PTdpbmLjJiOqwhlHdBTgOKBZVCgjIgyL79oV0EnayJeGTrOk71e9n5rpXFHzYKx7w7vCq9AzJnAkNJNzLHSc4QEKB0EqPEi9a9O4Ll06dw+n/wKygA3Jb422RgAAAABJRU5ErkJggg=='
    'zh-Hans' = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAACHklEQVQ4jWWTy24VRxRF16nu9jvCDxF5hIJQpoERM0ZMGPNDfA1/gJRR/oAMjBhFikBRIku+upaT4Fd3n70ZdN2H7Z5U1S7VOquOquP3X16+Inlu62lrfgxrJ6TgyfXQf938f1D+iz23maM8F+Uiw5cxjDfFKrJ2Ez0OxVMrn7eRvNuNeNFRDtvj2+C0gxKU46T/K0gaZPejdO4o89G+sHw5BrdBlIiy0ygeR+inOd5rJb3e32vYfnLLxpsZw2/75KdtynwTfu7xf8Fw2m5kxHGWcpwSwigCgDA0ARGF2WhaSXQb0L2Z0b09Y/y4A9pEf3aUZ1eQhcamAcBMX+AKxGDMYCOb1hK+LkSTDL8eoL9bSIGNe3APKMGeMhtksKZ5zWwjKpBrGD4coH86KIklyrMbkKY7iRWsAo0mu0VW91tbWEl+3gIJuwGJOOgZP24TKSzdNbQB18GYamiqoar+4qCE/uig912DqWEVtp5N46qHS4MV3LMyra3KWLPiHmwN3rpCFsAlXKsDD0HrBVbQpeEC6DXDh6DpeSyh6wWqzB3gIrR1r091/qB/3LnyytCiz0QWQ61iQ2AC09Q/oQWa+1awBF2vv8OZh29pfx3MLK0r7ARvRbBbxH6EjxrHYcEbDVAwUXs52gy2L5Xntk9aw/vzzBOFv8gxg7zUGBobtsLjrrPsR9GhiSOnj9rwo4AfCnQCj9LVDT6T/UWZJ98BB7RLvvMNl40AAAAASUVORK5CYII='
    'zh-Hant' = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAAB40lEQVQ4jaXTz2pTQRzF8c+de41tolhTKhUX/gFxqXQrQqHv4mvoukvfwYXP0E1duRCFoghuVFCIWhsq7U3T5M6MiySSCqWoB87mN8z3nIH5FVX15EFK6S7xJuWVdju067opQkjjGOMB459B2nvt8V6Q+pF91IFhJKCDlczNzN0qxvSI1r2cy2632yrW1rrG4+jly12DwQhJoRktyf2Cvch+pM4cZ0KgHVgpubHLhSrntEFbUVTW1695+PC2lLLNzTe2t3vIiK0VVjOrCXE6hQKlSdVvqEgIOp1gbe2yjY2rRqNka+uLFy++OT5uwPnpxZmykxpPZ1NgUhRZrzfw6tUPTZN8/nxodjbx6bCZ0jywrse2t3u+fq0dHTXevu1P22V5ijgNNB9UkZQa19K+i+8/OPo0MhxG14vgknP6Fv20eCbsd8N179x34JYfrjQHOs0xspHSofP62vYtKs5A5tkLnrmaa2XOnHD6Sw/Jz8nVHT2tP5L+VQlhHvA/sN/AGeh/YTNOlTHCEI3JFjDZgGDymas5F6c0O5oHfucw8qlht2FQEDMLgU5gKbBc0i1pVdOgMAXESaF8SD+xU+HpHjuRj4ndkjqRRiyUdDJLBd3EMpYrLpVcLDiXyA2DId8bPmLnFwByBs8DRkw6AAAAAElFTkSuQmCC'
}
$script:FlagBitmaps = @{}

function Get-FlagBitmap([string]$Code) {
    if ($script:FlagBitmaps.ContainsKey($Code)) { return $script:FlagBitmaps[$Code] }
    if ($script:FlagB64.ContainsKey($Code)) {
        try {
            $bytes = [System.Convert]::FromBase64String($script:FlagB64[$Code])
            $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
            $bmp = [System.Drawing.Bitmap]::FromStream($ms)
            $script:FlagBitmaps[$Code] = $bmp
            return $bmp
        } catch { }
    }
    return $null
}

# A-Z / Z-A column sorting for the song browser's ListView (ListViewItemSorter
# needs a real IComparer). A PowerShell `class ... : IComparer` can't be used
# here: its body is type-checked at PARSE time, before System.Windows.Forms
# is loaded (the Add-Type calls above run at execution time, too late for
# that check) - confirmed by a parse-time "Unable to find type
# [System.Windows.Forms.ListViewItem]" error, and `using assembly` doesn't
# resolve a GAC display name here either (it wants a real file path). A
# runtime-compiled Add-Type C# class sidesteps this: it compiles after
# System.Windows.Forms is already loaded.
if (-not ('LegacyDownloader.SongListSorter' -as [type])) {
    Add-Type -ReferencedAssemblies ([System.Windows.Forms.Application].Assembly.Location) -TypeDefinition @'
using System;
using System.Collections;
using System.Windows.Forms;
namespace LegacyDownloader {
    public class SongListSorter : IComparer {
        public int Column = 0;
        public bool Ascending = true;
        public int Compare(object a, object b) {
            ListViewItem ia = (ListViewItem)a;
            ListViewItem ib = (ListViewItem)b;
            // Share-only songs (not in the community sheet) are flagged by
            // giving their ListViewItem.Name "unknown" (Tag is already the
            // Edition|Code key everything else keys off, so this needed a
            // separate slot) - they sort first, ahead of the column
            // comparison and independent of Ascending, so they stay visible
            // at the top no matter what the list is sorted by.
            bool ua = ia.Name == "unknown";
            bool ub = ib.Name == "unknown";
            if (ua != ub) return ua ? -1 : 1;
            string sa = ia.SubItems[Column].Text;
            string sb = ib.SubItems[Column].Text;
            int r = string.Compare(sa, sb, StringComparison.OrdinalIgnoreCase);
            return Ascending ? r : -r;
        }
    }
}
'@
}

# EM_SETCUEBANNER via SendMessage - WinForms has no native TextBox
# placeholder-text property, and this P/Invoke is the standard workaround.
#
# The same Native class also carries the header-control sort arrow
# (HDM_SETITEM/HDF_SORTUP/HDF_SORTDOWN) plumbing: WinForms' ListView has no
# managed property for the native up/down sort glyph comctl32 already draws
# in the header - the previous code faked it by appending " ^"/" v" text to
# the column caption. SetSortArrow reaches into the ListView's underlying
# header control (via LVM_GETHEADER) and sets the real HDITEM format flag.
if (-not ('LegacyDownloader.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace LegacyDownloader {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct HDITEM {
        public int mask;
        public int cxy;
        public IntPtr pszText;
        public IntPtr hbm;
        public int cchTextMax;
        public int fmt;
        public IntPtr lParam;
        public int iImage;
        public int iOrder;
        public int type;
        public IntPtr pvFilter;
        public int state;
    }
    public class Native {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wParam, ref HDITEM lParam);

        const int LVM_GETHEADER = 0x101F;
        const int HDM_GETITEM = 0x120B;
        const int HDM_SETITEM = 0x120C;
        const int HDI_FORMAT = 0x0004;
        const int HDF_SORTUP = 0x0400;
        const int HDF_SORTDOWN = 0x0200;

        // direction: 0 = no arrow, 1 = ascending (up), -1 = descending (down).
        public static void SetSortArrow(IntPtr listViewHandle, int columnIndex, int direction) {
            IntPtr header = SendMessage(listViewHandle, LVM_GETHEADER, IntPtr.Zero, IntPtr.Zero);
            if (header == IntPtr.Zero) return;
            HDITEM item = new HDITEM();
            item.mask = HDI_FORMAT;
            SendMessage(header, HDM_GETITEM, columnIndex, ref item);
            item.fmt &= ~(HDF_SORTUP | HDF_SORTDOWN);
            if (direction > 0) item.fmt |= HDF_SORTUP;
            else if (direction < 0) item.fmt |= HDF_SORTDOWN;
            SendMessage(header, HDM_SETITEM, columnIndex, ref item);
        }
    }
}
'@
}

# ===========================================================================
# UI theme & helpers
# ===========================================================================

$script:FontFamilyUI = 'Segoe UI'
$script:FontBase     = New-Object System.Drawing.Font($script:FontFamilyUI, 9)
$script:FontBold     = New-Object System.Drawing.Font($script:FontFamilyUI, 9, [System.Drawing.FontStyle]::Bold)
$script:FontTitle    = New-Object System.Drawing.Font($script:FontFamilyUI, 9.5, [System.Drawing.FontStyle]::Bold)
$script:FontMono     = New-Object System.Drawing.Font('Consolas', 9)

$script:ColorBg      = [System.Drawing.Color]::FromArgb(246, 248, 250)
$script:ColorCard    = [System.Drawing.Color]::White
$script:ColorPrimary = [System.Drawing.Color]::FromArgb(18, 98, 200)
$script:ColorText    = [System.Drawing.Color]::FromArgb(30, 41, 59)
$script:ColorBorder  = [System.Drawing.Color]::FromArgb(203, 213, 225)
$script:ColorMuted   = [System.Drawing.Color]::FromArgb(100, 116, 139)

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 20) {
    $l = New-Object System.Windows.Forms.Label
    $l.Font = $script:FontBase
    $l.ForeColor = $script:ColorText
    $l.Text = $Text; $l.SetBounds($X, $Y, $W, $H); return $l
}

function New-Btn([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 28, [bool]$IsPrimary = $false) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.SetBounds($X, $Y, $W, $H)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($IsPrimary) {
        $b.Font = $script:FontTitle
        $b.BackColor = $script:ColorPrimary
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(15, 84, 172)
        $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(12, 71, 146)
    } else {
        $b.Font = $script:FontBase
        $b.BackColor = $script:ColorCard
        $b.ForeColor = $script:ColorText
        $b.FlatAppearance.BorderColor = $script:ColorBorder
        $b.FlatAppearance.BorderSize = 1
        # Explicit, not left at FlatAppearance's default (Color.Empty, which
        # is DOCUMENTED to make WinForms auto-compute a hover tint) - Ven
        # reported buttons showing no hover feedback in real use, and
        # spelling the colors out here removes any dependency on that
        # automatic behavior actually kicking in.
        $b.FlatAppearance.MouseOverBackColor = $script:ColorBg
        $b.FlatAppearance.MouseDownBackColor = $script:ColorBorder
    }
    return $b
}

function New-FilterDropdown([string[]]$Labels) {
    # A checkbox-per-row popup for "pick any of these" filtering, built from
    # ToolStripMenuItems in a ContextMenuStrip - the same control type the
    # "Columns..." menu already uses. A CheckedListBox (the original
    # implementation here) has no such thing as a per-row mouse-over
    # highlight at all - only click-selection - which is exactly why it
    # looked inert next to the Columns menu's native item hover (Ven
    # noticed the difference directly). ToolStripMenuItem gets that
    # highlight for free from the ToolStrip renderer.
    #
    # Closing is cancelled when caused by an item click, so the menu stays
    # open across multiple checkbox toggles in one visit - ContextMenuStrip
    # otherwise closes after ANY item click, which would force reopening it
    # for every single tier picked (the CheckedListBox version never had
    # this problem since it wasn't built from individually-closing items).
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $items = New-Object System.Collections.Generic.List[System.Windows.Forms.ToolStripMenuItem]
    foreach ($l in $Labels) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($l)
        # CheckOnClick left at its default ($false) - same reasoning as the
        # Columns menu: reading .Checked inside a click handler gives the
        # PRE-click state, so the caller (below) flips it explicitly instead.
        [void]$menu.Items.Add($mi)
        $items.Add($mi)
    }
    $menu.Add_Closing({
        param($s, $e)
        if ($e.CloseReason -eq [System.Windows.Forms.ToolStripDropDownCloseReason]::ItemClicked) { $e.Cancel = $true }
    })
    return @{ Menu = $menu; Items = $items }
}

function Info-Box([string]$Text, [string]$Title) {
    [System.Windows.Forms.MessageBox]::Show($script:Form, $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
function Warn-Box([string]$Text, [string]$Title) {
    [System.Windows.Forms.MessageBox]::Show($script:Form, $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}
function Ask-YesNo([string]$Text, [string]$Title) {
    return ([System.Windows.Forms.MessageBox]::Show($script:Form, $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes)
}
function Pick-Folder([string]$Desc, [string]$InitialPath) {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = $Desc; $d.ShowNewFolderButton = $true
    if (-not [string]::IsNullOrWhiteSpace($InitialPath) -and (Test-Path -LiteralPath $InitialPath)) {
        $d.SelectedPath = $InitialPath
    }
    $res = $d.ShowDialog($script:Form)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) { return $d.SelectedPath.TrimEnd('\') }
    return $null
}
function Format-Eta([int]$Seconds) {
    if ($Seconds -le 0) { return (T 'gui.eta_unknown') }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.TotalHours -ge 1) { return ('{0}h {1}m' -f [int]$ts.TotalHours, $ts.Minutes) }
    if ($ts.TotalMinutes -ge 1) { return ('{0}m {1}s' -f [int]$ts.TotalMinutes, $ts.Seconds) }
    return ('{0}s' -f $ts.Seconds)
}
function Append-Log([string]$Line) {
    if ($null -eq $script:TxtLog) { return }
    $script:TxtLog.AppendText($Line + "`r`n")
    # keep the newest line in view even when the box isn't focused
    $script:TxtLog.SelectionStart = $script:TxtLog.TextLength
    $script:TxtLog.ScrollToCaret()
}

# ===========================================================================
# background scan - Get-UpdatePlan runs in a child job (Start-Process -Wait
# inside rclone's capture deadlocks in an in-process runspace, but is fine in
# a real child powershell.exe), the plan comes back via Export-Clixml, and a
# Forms.Timer polls so the window stays responsive during a slow multi-
# edition scan.
# ===========================================================================

function Begin-Scan([bool]$IgnoreWrong) {
    $script:ScanIgnoredWrongLevel = $IgnoreWrong
    Set-Busy $true
    $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $script:LblProg.Text = T 'gui.progress_scanning'
    Append-Log (T 'gui.progress_scanning')

    $script:ScanOut = [System.IO.Path]::GetTempFileName()
    $script:ScanJob = Start-Job -ScriptBlock {
        param($mod, $dir, $lang, $gp, $eds, $songFilters, $ignore, $outFile)
        Import-Module $mod -DisableNameChecking
        $null = Initialize-LegacyCore -ScriptDir $dir
        $null = Initialize-Language -Code $lang
        $plan = if ($ignore) {
            Get-UpdatePlan -GamePath $gp -Editions $eds -SongFilters $songFilters -IgnoreWrongLevel
        } else {
            Get-UpdatePlan -GamePath $gp -Editions $eds -SongFilters $songFilters
        }
        $plan | Export-Clixml -Path $outFile
    } -ArgumentList $script:ModPath, $script:AppDir, (Get-LanguageCode), $script:Cfg.GamePath, $script:Cfg.Editions, $script:Cfg.SongFilters, $IgnoreWrong, $script:ScanOut

    $script:ScanTimer.Start()
}

function Poll-Scan {
    if (-not $script:ScanJob) { return }
    if ($script:ScanJob.State -eq 'Running' -or $script:ScanJob.State -eq 'NotStarted') { return }
    $script:ScanTimer.Stop()

    $job = $script:ScanJob; $script:ScanJob = $null
    $errMsg = $null
    try { Receive-Job $job -ErrorAction Stop | Out-Null } catch { $errMsg = $_.Exception.Message }
    if (-not $errMsg -and $job.State -eq 'Failed') {
        $r = $job.ChildJobs[0].JobStateInfo.Reason
        $errMsg = if ($r) { $r.Message } else { 'background scan failed' }
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    $plan = $null
    if (-not $errMsg) {
        try { if (Test-Path -LiteralPath $script:ScanOut) { $plan = Import-Clixml -LiteralPath $script:ScanOut } } catch { $errMsg = $_.Exception.Message }
    }
    Remove-Item -LiteralPath $script:ScanOut -Force -ErrorAction SilentlyContinue

    On-PlanReady $plan $errMsg $script:ScanIgnoredWrongLevel
}

# ===========================================================================
# download queue (Start-RcloneCopy + a Forms.Timer polling its JSON log)
# ===========================================================================

function Start-Downloads($Jobs) {
    $script:Queue = [System.Collections.ArrayList]::new()
    foreach ($j in $Jobs) { [void]$script:Queue.Add($j) }
    $script:Job = $null
    if ($null -eq $script:LoggedObjects) {
        $script:LoggedObjects = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    } else {
        $script:LoggedObjects.Clear()
    }
    Set-Busy $true
    $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $script:DlTimer.Start()
    Advance-Queue
}

function Advance-Queue {
    if ($script:Job) {
        # Flush any remaining objects before closing the job
        $finalStats = Read-RcloneStats -Job $script:Job
        if ($finalStats -and $finalStats.Objects) {
            foreach ($obj in $finalStats.Objects) {
                if ($script:LoggedObjects.Add($obj)) {
                    $cleanObj = $obj -replace '_pc\.ipk$', ''
                    Append-Log ("  $([char]0x2193) " + $cleanObj)
                }
            }
        }

        $code = Complete-RcloneCopy -Job $script:Job
        if ($code -eq 0) {
            Append-Log ("$([char]0x2713) " + (T 'gui.progress_done_line' @{ label = $script:Job.Label }))
            # The base job just wrote GamePath\Legacy.exe / Kinect*.dll / the
            # bundle+patch ipks (minus whatever the preview's checklist said
            # to keep) - record their new hashes now so the NEXT check can
            # tell "untouched since we wrote it" apart from "user changed it".
            if ($script:CurrentSpec -and $script:CurrentSpec.Kind -eq 'base') {
                Update-ProtectedFileHashes -GamePath $script:Cfg.GamePath -KeepFiles $script:CurrentSpec.Keep
            }
        } else {
            Append-Log ("$([char]0x2717) " + (T 'gui.progress_failed_line' @{ label = $script:Job.Label; code = $code }))
            $script:Job = $null
            $script:CurrentSpec = $null
            $script:DlTimer.Stop()
            Set-Busy $false
            Warn-Box (T 'gui.failed_body' @{ code = $code }) (T 'gui.failed_title')
            return
        }
        $script:Job = $null
        $script:CurrentSpec = $null
    }
    if ($script:Queue.Count -eq 0) { Finish-Downloads; return }
    $spec = $script:Queue[0]; $script:Queue.RemoveAt(0)
    $script:CurrentSpec = $spec
    $script:LoggedObjects.Clear()
    $script:LblProg.Text = T 'gui.progress_preparing' @{ label = $spec.Label }
    Append-Log (T 'gui.progress_preparing' @{ label = $spec.Label })
    $script:Job = Start-RcloneCopy -Source $spec.Source -Dest $spec.Dest -ExtraArgs $spec.Extra -Label $spec.Label
}

function Poll-Download {
    if (-not $script:Job) { return }
    $s = Read-RcloneStats -Job $script:Job
    if ($s) {
        if ($s.HasStats) {
            if ($s.TotalBytes -gt 0) {
                $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                $v = $s.Percent; if ($v -lt 0) { $v = 0 } elseif ($v -gt 100) { $v = 100 }
                $script:Bar.Value = $v
            } else {
                $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
            }
            $eta = if ($null -eq $s.Eta) { T 'gui.eta_unknown' } else { Format-Eta $s.Eta }
            $script:LblProg.Text = T 'gui.progress_downloading' @{
                label = $script:Job.Label; pct = $s.Percent
                speed = (Format-Bytes ([long]$s.Speed)); eta = $eta
            }
        }
        if ($s.Objects) {
            foreach ($obj in $s.Objects) {
                if ($script:LoggedObjects.Add($obj)) {
                    $cleanObj = $obj -replace '_pc\.ipk$', ''
                    Append-Log ("  $([char]0x2193) " + $cleanObj)
                }
            }
        }
    }
    if ($script:Job.Process.HasExited) { Advance-Queue }
}

function Finish-Downloads {
    $script:DlTimer.Stop()
    $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:Bar.Value = 100
    Set-Busy $false
    Refresh-FolderStatus
    Refresh-Tracking
    Append-Log "----"
    Append-Log ("$([char]0x2713) " + (T 'gui.done_title'))
    Info-Box (T 'gui.done_body') (T 'gui.done_title')
    Ensure-FirstRunRequirementsChecked
}

# One-time-only requirements check for a brand-new install ('get' from
# Run-SetupDialog - existing installs, which already have a config.txt,
# never hit Run-SetupDialog at all and so never hit this either; they only
# ever discover the feature through the main window's Requirements button).
# Called from both places a fresh 'get' setup can finish: a real download
# completing (Finish-Downloads) and the "nothing to download, already up to
# date" early-out in On-PlanReady - the folder-already-has-the-game branch
# of the first-run Add_Shown handler goes through On-Check, which can hit
# either exit depending on what's actually on disk.
function Ensure-FirstRunRequirementsChecked {
    if ($script:FirstRunMode -ne 'get' -or $script:ReqsFirstRunChecked) { return }
    $script:ReqsFirstRunChecked = $true
    Show-RequirementsDialog -FirstRun
    Refresh-RequirementsButton
}

function Build-DownloadQueue($Plan, $KeepFiles) {
    $gp = $script:Cfg.GamePath
    $jobs = @()

    $baseNeedsSync = (@($Plan.BaseNormal).Count -gt 0) -or (@($Plan.BaseAsk | Where-Object { $KeepFiles -notcontains $_ }).Count -gt 0)
    if ($baseNeedsSync -or $Plan.MapsMissing) {
        $ex = Get-BaseSyncExcludes -GamePath $gp -KeepFiles $KeepFiles
        $exArgs = @()
        foreach ($e in $ex) { $exArgs += @('--exclude', $e) }
        $jobs += @{ Label = (T 'gui.job_base'); Source = ($script:Conn + 'LegacyPC - Game'); Dest = $gp; Extra = $exArgs; Kind = 'base'; Keep = $KeepFiles }
    }

    if ($script:Cfg.Editions.ToUpper() -eq 'AUTO') {
        if (@($Plan.Songs).Count -gt 0) {
            $jobs += @{ Label = (T 'gui.job_allsongs'); Source = ($script:Conn + 'maps'); Dest = (Join-Path $gp 'maps'); Extra = @() }
        }
    } else {
        $planEditions = @($Plan.Songs | Where-Object { $_.Count -gt 0 } | ForEach-Object { [string]$_.Edition })
        if ($planEditions.Count -eq 0) {
            $planEditions = @($script:Cfg.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }
        foreach ($ed in $planEditions) {
            $dispLabel = Format-EditionDisplay $ed
            $extra = Get-SongIncludeArgs (Get-EffectiveSongs $ed $script:Cfg.SongFilters)
            $jobs += @{ Label = $dispLabel; Source = ($script:Conn + "maps/$ed"); Dest = (Join-Path $gp "maps\$ed"); Extra = $extra }
        }
    }
    return $jobs
}

# ===========================================================================
# plan -> text, and the preview / file-list dialogs
# ===========================================================================

function Build-PlanSummary($Plan) {
    $lines = @()
    $lines += (T 'gui.preview_intro')
    $lines += ''
    if ($Plan.GamePresent -and $Plan.MapsMissing) { $lines += (T 'preview.maps_missing_warn'); $lines += '' }

    $bn = @($Plan.BaseNormal).Count
    $ba = @($Plan.BaseAsk).Count
    if ($bn -gt 0) {
        $l = T 'preview.base_line' @{ count = $bn }
        if ($ba -gt 0) { $l += (T 'preview.base_line_mod_suffix' @{ count = $ba }) }
        $lines += $l
    } elseif ($ba -gt 0) {
        $lines += (T 'preview.base_mod_only' @{ count = $ba })
    } else {
        $lines += (T 'preview.base_up_to_date')
    }
    if ($Plan.KeptSettings) { $lines += (T 'preview.kept_settings') }

    if (@($Plan.Songs).Count -gt 0) {
        $lines += ''
        $lines += (T 'preview.songs_header')
        foreach ($s in $Plan.Songs) {
            $disp = Format-EditionDisplay $s.Edition
            $lines += (T 'preview.song_line' @{ edition = $disp.PadRight(12); count = $s.Count })
        }
    } else {
        $lines += (T 'preview.songs_up_to_date')
    }
    $lines += ''
    $lines += (T 'preview.total' @{ files = $Plan.TotalFiles; size = (Format-Bytes $Plan.TotalBytes) })
    return ($lines -join "`r`n")
}

function Show-FileListDialog($Plan, $KeepFiles) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'gui.filelist_title'
    $f.Font = $script:FontBase
    $f.BackColor = $script:ColorBg
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $f.ClientSize = New-Object System.Drawing.Size(480, 480)
    $f.MinimizeBox = $false; $f.MaximizeBox = $true

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true
    $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $tb.WordWrap = $false
    $tb.SetBounds(14, 14, 452, 410)
    $tb.Anchor = 'Top,Left,Right,Bottom'
    $tb.Font = $script:FontMono
    $tb.BackColor = $script:ColorCard
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lines = @()
    if (@($Plan.BaseNormal).Count -gt 0) {
        $lines += (T 'preview.list_base')
        foreach ($x in $Plan.BaseNormal) { $lines += "  $x" }
    }
    foreach ($x in $Plan.BaseAsk) {
        $tag = if ($KeepFiles -contains $x) { T 'gui.list_tag_keep' } else { T 'gui.list_tag_overwrite' }
        $lines += ("  {0}  ({1})" -f $x, $tag)
    }
    if ($Plan.KeptSettings) { $lines += (T 'preview.list_config') }
    if (@($Plan.SongFilesFlat).Count -gt 0) {
        $lines += (T 'preview.list_songs')
        foreach ($x in ($Plan.SongFilesFlat | Sort-Object)) { $lines += "  $x" }
    }
    $tb.Text = ($lines -join "`r`n")

    $ok = New-Btn (T 'gui.btn_ok') 376 436 90 30 $true
    $ok.Anchor = 'Bottom,Right'
    $ok.Add_Click({ param($s, $e) $f.Close() })
    $f.AcceptButton = $ok
    $f.Controls.AddRange(@($tb, $ok))
    $f.ShowDialog($script:Form) | Out-Null
    $f.Dispose()
}

function Show-PreviewDialog($Plan) {
    # returns @{ Proceed = $bool; Keep = @() }
    $out = @{ Proceed = $false; Keep = @() }
    $ba  = @($Plan.BaseAsk)
    $baSuspected = @($Plan.BaseAskSuspected)

    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'gui.preview_title'
    $f.Font = $script:FontBase
    $f.BackColor = $script:ColorBg
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $f.MinimizeBox = $false; $f.MaximizeBox = $false

    $summary = New-Object System.Windows.Forms.TextBox
    $summary.Multiline = $true; $summary.ReadOnly = $true
    $summary.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $summary.SetBounds(14, 14, 468, 180)
    $summary.Font = $script:FontMono
    $summary.BackColor = $script:ColorCard
    $summary.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $summary.Text = Build-PlanSummary $Plan

    $y = 204
    $clb = $null
    if ($ba.Count -gt 0) {
        $hintText = T 'gui.preview_moddable_hint'
        $hintSize = [System.Windows.Forms.TextRenderer]::MeasureText(
            $hintText, $script:FontBase, (New-Object System.Drawing.Size(468, 0)),
            [System.Windows.Forms.TextFormatFlags]::WordBreak)
        $hint = New-Label $hintText 14 $y 468 ($hintSize.Height + 6)
        $y += $hint.Height + 6
        $clb = New-Object System.Windows.Forms.CheckedListBox
        $clb.CheckOnClick = $true
        $clb.Font = $script:FontBase
        $clb.BackColor = $script:ColorCard
        $clb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $clb.SetBounds(14, $y, 468, ([Math]::Min(4, $ba.Count) * 20 + 8))
        # unchecked = keep yours, checked = take the update. Defaulted per item:
        # a file with real evidence of a post-sync change (BaseAskSuspected -
        # its hash used to match what we wrote, and no longer does) defaults
        # to unchecked/protect, same as always. A file with NO such evidence
        # (first time it's ever been checked under this logic, or a brand new
        # local copy) defaults to checked/take-the-update - otherwise a user
        # who never reads this list and just hits Enter would keep an old
        # Legacy.exe/Kinect DLL/bundle+patch ipk forever on nothing more than
        # "we've never asked about it before", which is the exact bug this
        # whole mechanism exists to fix.
        foreach ($x in $ba) { [void]$clb.Items.Add($x, ($baSuspected -notcontains $x)) }
        $y += $clb.Height + 12
        $f.Controls.Add($hint)
        $f.Controls.Add($clb)
    }

    # Widths are measured from the actual (translated) text so a longer
    # translation than English never gets clipped; Download stays centered
    # in whatever middle space is left between Files and Cancel.
    $btnFiles  = New-Btn (T 'gui.btn_show_files') 14 $y 0 32 $false
    $btnDl     = New-Btn (T 'gui.btn_download_now') 0 $y 0 32 $true
    $btnCancel = New-Btn (T 'gui.btn_cancel') 0 $y 0 32 $false
    foreach ($b in @($btnFiles, $btnDl, $btnCancel)) {
        $b.Width = [Math]::Max(90, [System.Windows.Forms.TextRenderer]::MeasureText($b.Text, $b.Font).Width + 28)
    }
    $btnCancel.Left = 496 - 14 - $btnCancel.Width
    $midStart = $btnFiles.Right + 10
    $midEnd = $btnCancel.Left - 10
    $btnDl.Left = $midStart + [Math]::Max(0, [int](($midEnd - $midStart - $btnDl.Width) / 2))
    $y += 46

    $btnFiles.Add_Click({
        param($s, $e)
        $keepNow = @()
        if ($clb) { for ($i = 0; $i -lt $clb.Items.Count; $i++) { if (-not $clb.GetItemChecked($i)) { $keepNow += [string]$clb.Items[$i] } } }
        Show-FileListDialog $Plan $keepNow
    })
    $btnDl.Add_Click({ param($s, $e) $f.Tag = 'go'; $f.Close() })
    $btnCancel.Add_Click({ param($s, $e) $f.Tag = ''; $f.Close() })

    $f.ClientSize = New-Object System.Drawing.Size(496, $y)
    $f.AcceptButton = $btnDl
    $f.CancelButton = $btnCancel
    $f.Controls.AddRange(@($summary, $btnFiles, $btnDl, $btnCancel))
    $f.ShowDialog($script:Form) | Out-Null

    if ($f.Tag -eq 'go') {
        $out.Proceed = $true
        if ($clb) {
            $keep = @()
            for ($i = 0; $i -lt $clb.Items.Count; $i++) { if (-not $clb.GetItemChecked($i)) { $keep += [string]$clb.Items[$i] } }
            $out.Keep = $keep
        }
    }
    $f.Dispose()
    return $out
}

# ===========================================================================
# maps / songs picker - editions checklist + grouped, sortable song list
# ===========================================================================
#
# One flat, sortable song list (grouped by edition via native ListView
# groups - no owner-drawing, no tree), plus a plain CheckedListBox of
# editions alongside it for one-click "get this whole edition". Both act on
# the same checked-set (Initialize-SongSelectionContext's SelectedKeys), kept
# in sync in both directions. Replaces an earlier TreeView-based design that
# had real owner-draw bugs: DrawString picked the wrong Graphics overload
# and clipped long titles, and the un-double-buffered TreeView flickered
# badly on every check/uncheck.
#
# The catalog fetch runs in the background (Start-Job, same pattern as the
# main window's Begin-Scan/Poll-Scan) so the dialog appears immediately with
# a loading indicator instead of blocking before the window is even shown.

function Show-SongBrowserDialog {
    # Returns $null (cancel) or @{ Editions = <csv>; SongFilters = <raw
    # SONGFILTERS string>; Catalog = <raw catalog array> } (Catalog lets the
    # caller run Get-SongRemovalPlan without a second fetch).
    #
    # -SeedFromDisk: seed the checked set from Get-LocalSongSelection (what's
    # actually downloaded) instead of $script:Cfg's own Editions/SongFilters.
    # Only used for the Everything -> Specific toggle, where config still
    # says AUTO (which Initialize-SongSelectionContext treats as "check the
    # entire catalog") even though nothing new was necessarily ever fetched
    # while Everything was briefly selected.
    param([switch]$SeedFromDisk)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'gui.songbrowser_title'
    $f.Font = $script:FontBase
    $f.BackColor = $script:ColorBg
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $f.MinimizeBox = $false; $f.MaximizeBox = $true
    $f.ShowIcon = $false
    $f.ClientSize = New-Object System.Drawing.Size(1000, 620)
    $f.MinimumSize = New-Object System.Drawing.Size(860, 460)

    # Right-pinned filter combos (fixed width, anchored Right) with the
    # search box stretching to fill the rest (anchored Left+Right) - keeps
    # the combos flush against the right edge at any window width.
    # Difficulty/Effort are buttons that open a checkbox-per-tier popup
    # (New-FilterDropdown) instead of a plain ComboBox, so more than one
    # tier can be selected at once - a real WinForms ComboBox has no
    # multi-select variant.
    $diffTierValues = @('unrated', '1', '2', '3', '4')
    $diffTierLabels = @((Format-DifficultyTier $null), (Format-DifficultyTier 1), (Format-DifficultyTier 2), (Format-DifficultyTier 3), (Format-DifficultyTier 4))
    $effTierValues  = @('0', '1', '2', '3', '4')
    $effTierLabels  = @((Format-EffortTier 0), (Format-EffortTier 1), (Format-EffortTier 2), (Format-EffortTier 3), (Format-EffortTier 4))

    $btnEffort = New-Btn (T 'gui.songbrowser_all_efforts') 826 14 160 24 $false
    $btnEffort.Anchor = 'Top,Right'
    $btnEffort.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $btnDifficulty = New-Btn (T 'gui.songbrowser_all_difficulties') 658 14 160 24 $false
    $btnDifficulty.Anchor = 'Top,Right'
    $btnDifficulty.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    # `u{25BE} is PowerShell 7+ string-escape syntax only - Windows
    # PowerShell 5.1 (what this runs on) doesn't support it and prints the
    # six characters literally, so build the dropdown-arrow suffix from a
    # [char] cast instead (works on both).
    $dropdownArrowSuffix = ' ' + [char]0x25BE

    # The fixed 160px width above was chosen to comfortably fit the widest
    # label in any of the 12 shipped languages, but for most actual text
    # ("All difficulties (dropdown arrow)" is nowhere near 160px in
    # English, and one-tier/no-filter is the common case) that left a lot
    # of dead space after the arrow, making the arrow read as floating in
    # the middle of an oversized button rather than sitting at a dropdown's
    # natural right edge - Ven's "does it even have an arrow" reaction.
    # Resizing both buttons to fit their OWN current text (recomputed every
    # time that text changes) fixes this for every language's actual
    # string, not just a guessed-at pixel number, while keeping them
    # right-aligned together at the same right margin ($btnUncheckShown's
    # own right edge, 986, one row down - reusing an already-established
    # anchor point) regardless of how wide either one currently is.
    $resizeFilterButtons = {
        $pad = 20
        $effWidth = [System.Windows.Forms.TextRenderer]::MeasureText($btnEffort.Text, $btnEffort.Font).Width + $pad
        $diffWidth = [System.Windows.Forms.TextRenderer]::MeasureText($btnDifficulty.Text, $btnDifficulty.Font).Width + $pad
        $rightEdge = 986
        $btnEffort.Width = $effWidth
        $btnEffort.Left = $rightEdge - $effWidth
        $btnDifficulty.Width = $diffWidth
        $btnDifficulty.Left = $btnEffort.Left - 8 - $diffWidth
    }

    $updateDifficultyButtonText = {
        $n = $script:SbDifficultyFilter.Count
        $btnDifficulty.Text = if ($n -eq 0) { (T 'gui.songbrowser_all_difficulties') + $dropdownArrowSuffix }
                              elseif ($n -eq 1) { $diffTierLabels[[Array]::IndexOf($diffTierValues, @($script:SbDifficultyFilter)[0])] + $dropdownArrowSuffix }
                              else { (T 'gui.songbrowser_n_selected' @{ count = $n }) + $dropdownArrowSuffix }
        & $resizeFilterButtons
    }
    $updateEffortButtonText = {
        $n = $script:SbEffortFilter.Count
        $btnEffort.Text = if ($n -eq 0) { (T 'gui.songbrowser_all_efforts') + $dropdownArrowSuffix }
                          elseif ($n -eq 1) { $effTierLabels[[Array]::IndexOf($effTierValues, @($script:SbEffortFilter)[0])] + $dropdownArrowSuffix }
                          else { (T 'gui.songbrowser_n_selected' @{ count = $n }) + $dropdownArrowSuffix }
        & $resizeFilterButtons
    }
    & $updateDifficultyButtonText
    & $updateEffortButtonText

    # Checkbox-per-tier popups built from ToolStripMenuItems (see
    # New-FilterDropdown) instead of a CheckedListBox - a CheckedListBox has
    # no per-row mouse-over highlight at all (only click-selection), which
    # is why it looked inert next to the "Columns..." menu's native item
    # hover; ToolStripMenuItem gets that for free from the same renderer
    # the Columns menu already uses. $applyDifficultyFilterToggle/
    # $applyEffortFilterToggle are pulled out as their own named
    # scriptblocks for the same reason $toggleColumnVisibility is: a
    # ContextMenuStrip is a separate top-level popup with no supported way
    # to fire a real click on it from code, so self-test calls these
    # directly instead.
    $diffPopup = New-FilterDropdown $diffTierLabels
    $applyDifficultyFilterToggle = {
        param([int]$Index, [bool]$Checked)
        $diffPopup.Items[$Index].Checked = $Checked
        $val = $diffTierValues[$Index]
        if ($Checked) { [void]$script:SbDifficultyFilter.Add($val) } else { [void]$script:SbDifficultyFilter.Remove($val) }
        & $updateDifficultyButtonText
        & $refreshList
    }
    $diffPopup.Menu.Add_ItemClicked({
        param($s, $e)
        $idx = $diffPopup.Items.IndexOf($e.ClickedItem)
        if ($idx -lt 0) { return }
        & $applyDifficultyFilterToggle $idx (-not $e.ClickedItem.Checked)
    })
    $btnDifficulty.Add_Click({ param($s, $e) $diffPopup.Menu.Show($btnDifficulty, (New-Object System.Drawing.Point(0, $btnDifficulty.Height))) })

    $effPopup = New-FilterDropdown $effTierLabels
    $applyEffortFilterToggle = {
        param([int]$Index, [bool]$Checked)
        $effPopup.Items[$Index].Checked = $Checked
        $val = $effTierValues[$Index]
        if ($Checked) { [void]$script:SbEffortFilter.Add($val) } else { [void]$script:SbEffortFilter.Remove($val) }
        & $updateEffortButtonText
        & $refreshList
    }
    $effPopup.Menu.Add_ItemClicked({
        param($s, $e)
        $idx = $effPopup.Items.IndexOf($e.ClickedItem)
        if ($idx -lt 0) { return }
        & $applyEffortFilterToggle $idx (-not $e.ClickedItem.Checked)
    })
    $btnEffort.Add_Click({ param($s, $e) $effPopup.Menu.Show($btnEffort, (New-Object System.Drawing.Point(0, $btnEffort.Height))) })

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.SetBounds(14, 14, 636, 24)
    $txtSearch.Anchor = 'Top,Left,Right'
    $txtSearch.Font = $script:FontBase

    # Plain WinForms TextBox has a real, long-documented quirk: Ctrl+Backspace
    # does NOT delete the previous word the way every native Windows edit
    # control (and every other app) does - it inserts the raw DEL control
    # character (0x7F) as literal text instead, which renders as a stray
    # box/blank glyph rather than erasing anything (exactly what Ven
    # reported: "doesn't erase and instead writes... idk what it writes").
    # SuppressKeyPress stops that default insertion; the word-delete below
    # (trailing whitespace, then the run of non-whitespace before it) is the
    # conventional Ctrl+Backspace behavior other apps implement.
    $txtSearch.Add_KeyDown({
        param($s, $e)
        if (-not ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Back)) { return }
        $e.SuppressKeyPress = $true
        if ($txtSearch.SelectionLength -gt 0) { $txtSearch.SelectedText = ''; return }
        $pos = $txtSearch.SelectionStart
        if ($pos -eq 0) { return }
        $text = $txtSearch.Text
        $i = $pos
        while ($i -gt 0 -and [char]::IsWhiteSpace($text[$i - 1])) { $i-- }
        while ($i -gt 0 -and -not [char]::IsWhiteSpace($text[$i - 1])) { $i-- }
        $txtSearch.Text = $text.Substring(0, $i) + $text.Substring($pos)
        $txtSearch.SelectionStart = $i
    })

    # Small overlaid "x" button to clear the search box in one click -
    # there's no native "clear text box" property/control on a WinForms
    # TextBox (Ven asked), so this fakes the common modern-search-box
    # pattern instead: a borderless button positioned over the textbox's
    # own right edge, shown only while there's something to clear.
    # $txtSearch is Anchor='Top,Left,Right' (the dialog is resizable), so
    # its right edge moves as the window resizes - reposition on every
    # SizeChanged rather than relying on this button's own Anchor, which
    # has no way to track another control's dynamic edge.
    $btnClearSearch = New-Object System.Windows.Forms.Button
    $btnClearSearch.Text = [string][char]0x00D7
    $btnClearSearch.Font = $script:FontBase
    $btnClearSearch.Size = New-Object System.Drawing.Size(20, 20)
    $btnClearSearch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClearSearch.FlatAppearance.BorderSize = 0
    $btnClearSearch.FlatAppearance.MouseOverBackColor = $script:ColorBg
    $btnClearSearch.FlatAppearance.MouseDownBackColor = $script:ColorBorder
    # Transparent, not a solid fill color: at rest this lets whatever's
    # actually behind it show through (the textbox's own white interior)
    # instead of painting an opaque square that visibly cut across the
    # textbox's own border outline where the two overlapped. Only the glyph
    # itself needs to stay solid - ForeColor/Text painting is unaffected by
    # BackColor, and FlatAppearance's Mouse*BackColor above still paint a
    # real opaque fill on hover/press regardless of the resting BackColor.
    $btnClearSearch.BackColor = [System.Drawing.Color]::Transparent
    $btnClearSearch.ForeColor = $script:ColorMuted
    $btnClearSearch.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClearSearch.TabStop = $false
    $btnClearSearch.Visible = $false
    $repositionClearSearchBtn = {
        # Inset further than a snug fit (3px from the right edge, vertically
        # centered with room to spare) so the button's own bounding
        # rectangle never reaches the textbox's 1-2px border stroke at all -
        # transparency alone doesn't help if the button is still physically
        # sitting ON the border pixels themselves.
        $btnClearSearch.Location = New-Object System.Drawing.Point(
            ($txtSearch.Right - $btnClearSearch.Width - 3),
            ($txtSearch.Top + [int](($txtSearch.Height - $btnClearSearch.Height) / 2)))
    }
    $txtSearch.Add_SizeChanged({ & $repositionClearSearchBtn })
    & $repositionClearSearchBtn
    $txtSearch.Add_TextChanged({ $btnClearSearch.Visible = ($txtSearch.Text.Length -gt 0) })
    $btnClearSearch.Add_Click({ param($s, $e) $txtSearch.Text = ''; $txtSearch.Focus() })

    $lblEditions = New-Label (T 'gui.songbrowser_editions_header') 14 44 240 18
    $lblEditions.Font = $script:FontBold

    # DataGridView, not CheckedListBox: the checkbox column's ThreeState
    # rendering gives the real solid-square partial-selection glyph
    # natively (confirmed in an isolated test script) - CheckedListBox's
    # own SetItemCheckState(Indeterminate) always rendered a grayed
    # checkmark instead, and three separate owner-draw attempts to fix
    # that on CheckedListBox itself all failed for genuinely different
    # reasons (see docs/notes/handoff-2026-09-14-songpicker-polish.md).
    # Column 0 (checkbox) is ReadOnly with EditMode = EditProgrammatically,
    # so WinForms' own click-to-toggle/cycle-through-Indeterminate
    # behavior never engages at all - $clbEditions.Add_CellContentClick
    # below (near $applyEditionCheck) does 100% of the state-transition
    # decision itself instead, which sidesteps ever needing to know or
    # rely on what order a native ThreeState column would otherwise cycle
    # clicks through.
    $clbEditions = New-Object System.Windows.Forms.DataGridView
    $clbEditions.SetBounds(14, 66, 240, 500)
    $clbEditions.Anchor = 'Top,Left,Bottom'
    $clbEditions.Font = $script:FontBase
    $clbEditions.BackgroundColor = $script:ColorCard
    # BorderStyle.None (not the DataGridView default of Fixed3D) would drop
    # the outline around the whole list entirely - CellBorderStyle.None only
    # turns off the grid lines BETWEEN cells/rows, which is the part that
    # actually needs to go for this to look like a plain checkbox list
    # rather than a spreadsheet.
    $clbEditions.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $clbEditions.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::None
    $clbEditions.ColumnHeadersVisible = $false
    $clbEditions.RowHeadersVisible = $false
    $clbEditions.AllowUserToAddRows = $false
    $clbEditions.AllowUserToDeleteRows = $false
    $clbEditions.AllowUserToResizeRows = $false
    $clbEditions.AllowUserToResizeColumns = $false
    $clbEditions.MultiSelect = $false
    $clbEditions.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $clbEditions.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditProgrammatically
    $clbEditions.StandardTab = $false
    $clbEditions.RowTemplate.Height = 20
    $clbEditions.DefaultCellStyle.BackColor = $script:ColorCard
    $clbEditions.DefaultCellStyle.ForeColor = $script:ColorText
    $clbEditions.DefaultCellStyle.SelectionBackColor = $script:ColorPrimary
    $clbEditions.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $clbEditions.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)

    $colEditionCheck = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colEditionCheck.ThreeState = $true
    $colEditionCheck.Width = 24
    $colEditionCheck.ReadOnly = $true
    $colEditionCheck.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
    $colEditionCheck.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    [void]$clbEditions.Columns.Add($colEditionCheck)

    $colEditionLabel = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colEditionLabel.ReadOnly = $true
    $colEditionLabel.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $colEditionLabel.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    [void]$clbEditions.Columns.Add($colEditionLabel)

    $btnColumns = New-Btn (T 'gui.songbrowser_btn_columns') 596 42 94 22 $false
    $btnColumns.Anchor = 'Top,Right'
    $btnCheckShown = New-Btn (T 'gui.songbrowser_btn_check_shown') 698 42 130 22 $false
    $btnCheckShown.Anchor = 'Top,Right'
    $btnUncheckShown = New-Btn (T 'gui.songbrowser_btn_uncheck_shown') 836 42 150 22 $false
    $btnUncheckShown.Anchor = 'Top,Right'

    # The fixed widths above were sized for the English text and clip
    # longer translations (e.g. Korean's "표시된 항목 모두 선택"). Their text
    # never changes after construction (unlike Difficulty/Effort, which
    # re-run $resizeFilterButtons on every filter change), so a one-time
    # resize-to-fit here is enough - same MeasureText/pad/right-margin
    # pattern as $resizeFilterButtons above, right-aligned together at the
    # same right edge (986) that row already uses.
    $pad = 20
    $rightEdge = 986
    $btnUncheckShown.Width = [System.Windows.Forms.TextRenderer]::MeasureText($btnUncheckShown.Text, $btnUncheckShown.Font).Width + $pad
    $btnUncheckShown.Left = $rightEdge - $btnUncheckShown.Width
    $btnCheckShown.Width = [System.Windows.Forms.TextRenderer]::MeasureText($btnCheckShown.Text, $btnCheckShown.Font).Width + $pad
    $btnCheckShown.Left = $btnUncheckShown.Left - 8 - $btnCheckShown.Width
    $btnColumns.Width = [System.Windows.Forms.TextRenderer]::MeasureText($btnColumns.Text, $btnColumns.Font).Width + $pad
    $btnColumns.Left = $btnCheckShown.Left - 8 - $btnColumns.Width

    $lv = New-Object System.Windows.Forms.ListView
    $lv.SetBounds(268, 66, 718, 500)
    $lv.Anchor = 'Top,Left,Right,Bottom'
    $lv.View = [System.Windows.Forms.View]::Details
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.HideSelection = $false
    $lv.AllowColumnReorder = $true
    $lv.Font = $script:FontBase
    $lv.BackColor = $script:ColorCard
    $lv.Visible = $false

    # Columns are data-driven (key -> header/width/value-getter) rather than
    # hardcoded, so hiding/showing one via the Columns... menu just means
    # dropping/re-adding its key in $script:SbVisibleFieldKeys - ListView
    # pairs ListViewItem.SubItems[i] with Columns[i] by COLLECTION index
    # (not DisplayIndex, which AllowColumnReorder above only changes visual
    # position of), so removing a column from the middle of a fixed subitem
    # list would misalign every column after it. Building both the columns
    # AND each row's subitems from this same ordered key list every time
    # sidesteps that: there's only ever one source of truth for "which
    # fields, in what order".
    $fieldByKey = [ordered]@{
        Code       = @{ Header = (T 'gui.songbrowser_col_codename');   Width = 110; Value = { param($r) [string]$r.Code } }
        # A share-only (IsUnknown) row has no sheet data to build a real
        # title from - "{edition}/{code}_pc.ipk" (Ven's explicit call) gives
        # the user enough to place it (which edition/year it's from) without
        # a generic "not found" notice, and it's raw data (a codename + a
        # share path), not a translatable sentence, so it isn't run through
        # T/i18n at all.
        Title      = @{ Header = (T 'gui.songbrowser_col_title');      Width = 210; Value = { param($r) if ($r.IsUnknown) { "$($r.Edition)/$($r.Code)_pc.ipk" } elseif ([string]::IsNullOrWhiteSpace($r.Title)) { $r.Code } else { $r.Title } } }
        Artist     = @{ Header = (T 'gui.songbrowser_col_artist');     Width = 150; Value = { param($r) if ($r.IsUnknown) { '' } else { [string]$r.Artist } } }
        Difficulty = @{ Header = (T 'gui.songbrowser_col_difficulty'); Width = 80;  Value = { param($r) if ($r.IsUnknown) { '' } else { Format-DifficultyTier $r.Difficulty } } }
        Effort     = @{ Header = (T 'gui.songbrowser_col_effort');     Width = 80;  Value = { param($r) if ($r.IsUnknown) { '' } else { Format-EffortTier $r.Effort } } }
    }
    $script:SbVisibleFieldKeys = @($fieldByKey.Keys)

    # Format-DifficultyTier/Format-EffortTier are pure functions over a tiny
    # domain (tiers 1-4, efforts 0-4, plus "unrated") but were being called
    # once per ROW (up to ~2000 calls total) inside $computeFieldCache below
    # - profiling traced ~700ms of the multi-second dialog-open freeze to
    # just those calls (~0.35ms each; calling into a module-exported
    # function from deep inside this dialog's closures carries real
    # overhead that a cheap-looking function body doesn't suggest). Calling
    # each exactly once per distinct tier value here and looking the result
    # up by key in $computeFieldCache cuts ~2000 calls down to ~10.
    $diffTextByKey = @{}
    foreach ($t in 1..4) { $diffTextByKey["$t"] = Format-DifficultyTier $t }
    $diffTextByKey['unrated'] = Format-DifficultyTier $null
    $effTextByKey = @{}
    foreach ($t in 0..4) { $effTextByKey["$t"] = Format-EffortTier $t }
    $effTextByKey['unrated'] = Format-EffortTier $null

    $computeFieldCache = {
        # Every row's Title/Artist/Difficulty/Effort/Code text is fixed once
        # the catalog is loaded (or a share-only row is merged in) - it never
        # changes as the user searches, filters, switches editions, or
        # resorts. $refreshList used to call $fieldByKey[$k].Value (a
        # PowerShell scriptblock, real per-call overhead) for every field of
        # every VISIBLE row on every single one of those actions - for the
        # "switch from an edition back to All" case that's up to ~1000 rows
        # x 5 fields = ~5000 scriptblock invocations, measured at over 2
        # SECONDS on a real catalog. Computing each row's values exactly
        # once here (right after the row is created) and having
        # $refreshList do a plain hashtable lookup instead turns that into a
        # one-time cost paid at load/merge time, not on every filter/search/
        # edition-switch.
        #
        # This one-time cost still turned out to be the real cause of a
        # multi-second freeze right when the dialog's catalog finishes
        # loading (Ven: loads fine for ~2s, then freezes for a few more,
        # then fine) - it runs synchronously on the UI thread from
        # $populateFromCatalog/$applyUnknownSongs. Profiled against the
        # real catalog and fixed with $diffTextByKey/$effTextByKey above
        # (the dominant cost) plus storing the result in $script:SbFieldCache
        # (keyed by "Edition|Code", the same key $refreshList already
        # computes for Tag/Checked) instead of Add-Member'ing a FieldCache
        # property onto each row - Add-Member goes through the extended
        # type system and measured as a real, if smaller, avoidable cost of
        # its own. Combined: roughly 1700-2400ms -> well under 100ms for a
        # full ~1000-row catalog, measured in this actual dialog.
        param($r)
        $cache = @{}
        $cache['Code'] = [string]$r.Code
        $cache['Title'] = if ($r.IsUnknown) { "$($r.Edition)/$($r.Code)_pc.ipk" } elseif ([string]::IsNullOrWhiteSpace($r.Title)) { $r.Code } else { $r.Title }
        $cache['Artist'] = if ($r.IsUnknown) { '' } else { [string]$r.Artist }
        if ($r.IsUnknown) {
            $cache['Difficulty'] = ''
            $cache['Effort'] = ''
        } else {
            # Same normalization $refreshList's Difficulty/Effort filters
            # already use: Difficulty's "not rated" is the ABSENCE of a
            # valid 1-4 tier; Effort's 0 is itself a real, valid tier value.
            $dKey = if ($null -ne $r.Difficulty -and [int]$r.Difficulty -ge 1 -and [int]$r.Difficulty -le 4) { [string][int]$r.Difficulty } else { 'unrated' }
            $eKey = if ($null -ne $r.Effort -and [int]$r.Effort -ge 0 -and [int]$r.Effort -le 4) { [string][int]$r.Effort } else { 'unrated' }
            $cache['Difficulty'] = $diffTextByKey[$dKey]
            $cache['Effort'] = $effTextByKey[$eKey]
        }
        $script:SbFieldCache["$($r.Edition)|$($r.Code)"] = $cache
    }

    $rebuildColumns = {
        $lv.Columns.Clear()
        foreach ($key in $script:SbVisibleFieldKeys) { [void]$lv.Columns.Add($fieldByKey[$key].Header, $fieldByKey[$key].Width) }
    }
    & $rebuildColumns
    $sorter = New-Object LegacyDownloader.SongListSorter
    # Default sort is Title A-Z (not whichever field the reordered default
    # column layout happens to put first) - falls back to column 0 only if
    # Title somehow isn't in the visible set.
    $defaultSortCol = [Array]::IndexOf($script:SbVisibleFieldKeys, 'Title')
    if ($defaultSortCol -lt 0) { $defaultSortCol = 0 }
    $sorter.Column = $defaultSortCol
    $lv.ListViewItemSorter = $sorter

    # Every field (Title included) is toggleable; $toggleColumnVisibility
    # below refuses to hide the last remaining one, so there's always at
    # least one column left to show/sort/search by.
    $columnMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $columnMenuItems = @{}
    foreach ($key in $fieldByKey.Keys) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($fieldByKey[$key].Header)
        # CheckOnClick left at its default ($false) and .Checked flipped by
        # hand in ItemClicked below, rather than trusted to already hold
        # the post-click value there - empirically (Ven found this in real
        # use) reading .Checked inside a ContextMenuStrip's ItemClicked
        # handler gave the PRE-click state, inverting every toggle.
        $mi.Checked = $true
        $mi.Tag = $key
        [void]$columnMenu.Items.Add($mi)
        $columnMenuItems[$key] = $mi
    }
    $toggleColumnVisibility = {
        # Pulled out of the menu's ItemClicked handler as its own named
        # scriptblock so it (and therefore the whole feature) can be
        # exercised directly in the self-test below - a ContextMenuStrip is
        # a separate top-level popup window with no supported way to fire
        # its click event without a real mouse click.
        # Returns $true if the change was applied, $false if refused (the
        # caller uses this to decide whether to flip the menu item's own
        # checkmark, so a refused hide doesn't visually uncheck something
        # that's still actually shown).
        param([string]$Key, [bool]$Visible)
        if (-not $Visible -and $script:SbVisibleFieldKeys.Count -le 1) { return $false }
        $keys = [System.Collections.Generic.List[string]]::new([string[]]$script:SbVisibleFieldKeys)
        if ($Visible) {
            if (-not $keys.Contains($Key)) {
                # Re-insert at its canonical position among ALL fields (not
                # just the toggleable ones) so re-enabling a column doesn't
                # always dump it at the end regardless of where it started.
                $canonicalOrder = @($fieldByKey.Keys)
                $insertAt = 0
                foreach ($k in $keys) {
                    if ([Array]::IndexOf($canonicalOrder, $k) -lt [Array]::IndexOf($canonicalOrder, $Key)) { $insertAt++ }
                }
                $keys.Insert($insertAt, $Key)
            }
        } else {
            [void]$keys.Remove($Key)
        }
        $script:SbVisibleFieldKeys = @($keys)
        & $rebuildColumns
        $script:SbSort.Column = 0; $script:SbSort.Ascending = $true
        $sorter.Column = 0; $sorter.Ascending = $true
        & $refreshList
        & $updateSortArrows
        return $true
    }

    $columnMenu.Add_ItemClicked({
        param($s, $e)
        $key = $e.ClickedItem.Tag
        if ($null -eq $key) { return }
        $newVisible = -not $e.ClickedItem.Checked
        if (& $toggleColumnVisibility $key $newVisible) { $e.ClickedItem.Checked = $newVisible }
    })
    $btnColumns.Add_Click({ param($s, $e) $columnMenu.Show($btnColumns, (New-Object System.Drawing.Point(0, $btnColumns.Height))) })

    $barLoading = New-Object System.Windows.Forms.ProgressBar
    $barLoading.SetBounds(268, 66, 718, 18)
    $barLoading.Anchor = 'Top,Left,Right'
    $barLoading.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $barLoading.MarqueeAnimationSpeed = 30

    $lblStatus = New-Label (T 'songbrowser.loading') 14 578 772 20
    $lblStatus.ForeColor = $script:ColorMuted
    $lblStatus.Anchor = 'Bottom,Left,Right'

    $btnOk = New-Btn (T 'gui.btn_ok') 808 574 90 30 $true
    $btnOk.Anchor = 'Bottom,Right'
    $btnOk.Enabled = $false
    $btnCancel = New-Btn (T 'gui.btn_cancel') 906 574 80 30 $false
    $btnCancel.Anchor = 'Bottom,Right'

    $f.Controls.AddRange(@($txtSearch, $btnClearSearch, $btnDifficulty, $btnEffort, $lblEditions, $clbEditions, $btnColumns, $btnCheckShown, $btnUncheckShown, $lv, $barLoading, $lblStatus, $btnOk, $btnCancel))
    $btnClearSearch.BringToFront()
    foreach ($c in @($txtSearch, $btnDifficulty, $btnEffort, $clbEditions, $btnColumns, $btnCheckShown, $btnUncheckShown)) { $c.Enabled = $false }

    # EM_SETCUEBANNER: WinForms TextBox has no native placeholder-text
    # property, so the grey search hint needs a raw SendMessage call. The
    # handle must exist first - touching .Handle forces its creation.
    [void]$txtSearch.Handle
    [void][LegacyDownloader.Native]::SendMessage($txtSearch.Handle, 0x1501, [IntPtr]::Zero, (T 'gui.songbrowser_search_hint'))

    # Shared mutable state, read and reassigned across several scriptblocks
    # below (the Timer tick that finishes loading, column-click sort, every
    # checkbox handler). A scriptblock invoked via "&" runs in its own child
    # scope, so a plain local variable REASSIGNED inside one of them (like
    # $SbCtx would be, once the catalog loads) would not be visible to the
    # others - script scope sidesteps that entirely.
    $script:SbCtx             = $null
    $script:SbCatalog         = $null
    # Per-row cached field text (Code/Title/Artist/Difficulty/Effort),
    # keyed by "Edition|Code" - see $computeFieldCache. A plain hashtable
    # keyed by the same "Edition|Code" string $refreshList already builds
    # for Tag/Checked lookups, not an Add-Member'd property on each row:
    # profiling found Add-Member itself costing real time (~0.3-0.4ms x
    # ~1000 rows) on top of the scriptblock-dispatch cost it was already
    # paying for.
    $script:SbFieldCache      = @{}
    $script:SbEditionCodes    = @()
    $script:SbFilterEdition   = $null
    $script:SbSyncingEditions = $false
    $script:SbSyncingList     = $false
    $script:SbSort            = @{ Column = $defaultSortCol; Ascending = $true }
    # Empty set = no filter (show every tier), matching how the plain
    # "All difficulties"/"All efforts" dropdown option used to behave.
    $script:SbDifficultyFilter = New-Object System.Collections.Generic.HashSet[string]
    $script:SbEffortFilter     = New-Object System.Collections.Generic.HashSet[string]

    # ListView.ItemChecked (and, to be safe, CheckedListBox.ItemCheck) don't
    # necessarily fire synchronously while a checkbox state is being set in
    # code - a native ListView especially can defer/batch its notifications
    # until the message pump next runs. Resetting a "we're the ones causing
    # this, ignore it" guard flag immediately after the loop that set those
    # states is too early: the deferred events then fire later (during a
    # later DoEvents/pump cycle) with the guard already back to $false,
    # re-entering the same handlers and corrupting ListView state - this was
    # confirmed as the cause of a real crash (isolated with a standalone
    # repro) before this fix. BeginInvoke defers the reset itself to run
    # only after every already-queued message (including those deferred
    # notifications) has been dispatched.
    $deferGuardReset = {
        param([scriptblock]$Action)
        # Control.BeginInvoke(Delegate) takes the ABSTRACT Delegate type, so
        # PowerShell can't infer which concrete delegate to build from a bare
        # [scriptblock] variable and fails to bind any overload at all
        # ("Cannot find an overload for BeginInvoke and the argument count 1"
        # - the actual runtime error this cast fixes). Casting to [Action]
        # first gives it a concrete type to construct.
        if ($f.IsHandleCreated) { $f.BeginInvoke([Action]$Action) | Out-Null } else { & $Action }
    }

    $updateStatusLabel = {
        # Shared by every place that sets $lblStatus.Text, so the "still
        # scanning the share" note (below) shows up everywhere the normal
        # shown/total/selected status does, not just some of them. Without
        # this, a song that's only on the share (not the sheet) could be
        # genuinely absent from the list for as long as that whole ~24-
        # edition scan takes to finish - the merge only happens once, after
        # every edition has been checked, not edition-by-edition - and with
        # nothing on screen saying so, that reads as a bug rather than "not
        # done loading yet".
        if ($null -eq $script:SbCtx) { return }
        $text = T 'gui.songbrowser_status' @{ shown = $lv.Items.Count; total = $script:SbCtx.Rows.Count; selected = $script:SbCtx.SelectedKeys.Count }
        if (-not $script:SbUnknownJobDone) { $text += ' ' + (T 'gui.songbrowser_scanning_share') }
        $lblStatus.Text = $text
    }

    $refreshEditionCheckboxes = {
        # Recomputes EVERY clbEditions row's label + checked state (real
        # editions at 1..N, the "All" pseudo-entry at 0) from
        # $script:SbCtx.SelectedKeys in one guarded pass, rather than
        # hand-patching just the row(s) a given action "should" affect.
        # Deliberately does not touch $lv.Groups/ListViewGroup at all:
        # ListViewGroup.set_Header forces WinForms to destroy and recreate
        # the ListView's window handle (RecreateHandleInternal) once the
        # list already has one, and doing that from inside the ListView's
        # own ItemChecked handler is reentrant on that control's own WndProc
        # - this is what threw "Error creating window handle" and left the
        # ListView's handle state corrupted for the rest of the dialog
        # (every later operation on it then crashed with a
        # NullReferenceException in OnHandleDestroyed). Native ListView
        # grouping was dropped entirely in favor of the flat, clbEditions-
        # filtered list below, so this class of bug cannot recur.
        #
        # Writing Cells[].Value here only ever raises DataGridView's
        # CellValueChanged - nothing below listens for that (the real
        # state-transition logic lives in $applyEditionCheck, driven by
        # CellContentClick/$setEditionChecked instead), so this loop can
        # never re-enter itself the way CheckedListBox could.
        if ($null -eq $script:SbCtx) { return }
        $script:SbSyncingEditions = $true
        $totalChecked = 0
        # Plain foreach+if instead of Where-Object/pipeline: with ~1000 rows
        # across ~24 editions, pipeline overhead here was measurable too,
        # though the real cost behind "ticking a song/edition takes a while
        # to update" turned out to be the reentrant $refreshList guarded
        # against in clbEditions's SelectionChanged handler below.
        for ($i = 0; $i -lt $script:SbEditionCodes.Count; $i++) {
            $ed = $script:SbEditionCodes[$i]
            $codes = $script:SbCtx.ByEdition[$ed]
            $checkedCount = 0
            foreach ($code in $codes) { if ($script:SbCtx.SelectedKeys.Contains("$ed|$code")) { $checkedCount++ } }
            $totalChecked += $checkedCount
            $count = $codes.Count
            $disp = Format-EditionDisplay $ed
            $label = if ($checkedCount -gt 0 -and $checkedCount -lt $count) { "$disp ($checkedCount/$count)" } else { "$disp ($count)" }
            $row = $clbEditions.Rows[$i + 1]
            if ($row.Cells[1].Value -ne $label) { $row.Cells[1].Value = $label }
            # Indeterminate (the classic half-filled "partial selection"
            # square) for some-but-not-all checked - the ThreeState
            # checkbox column renders this as a real solid square natively,
            # no owner-draw needed.
            $state = if ($count -eq 0 -or $checkedCount -eq 0) { [System.Windows.Forms.CheckState]::Unchecked }
                     elseif ($checkedCount -eq $count) { [System.Windows.Forms.CheckState]::Checked }
                     else { [System.Windows.Forms.CheckState]::Indeterminate }
            if ($row.Cells[0].Value -ne $state) { $row.Cells[0].Value = $state }
        }
        $total = $script:SbCtx.Rows.Count
        $allLabel = if ($total -gt 0) { "$(T 'gui.songbrowser_all_editions') ($totalChecked/$total)" } else { T 'gui.songbrowser_all_editions' }
        $allRow = $clbEditions.Rows[0]
        if ($allRow.Cells[1].Value -ne $allLabel) { $allRow.Cells[1].Value = $allLabel }
        $allState = if ($total -eq 0 -or $totalChecked -eq 0) { [System.Windows.Forms.CheckState]::Unchecked }
                    elseif ($totalChecked -eq $total) { [System.Windows.Forms.CheckState]::Checked }
                    else { [System.Windows.Forms.CheckState]::Indeterminate }
        if ($allRow.Cells[0].Value -ne $allState) { $allRow.Cells[0].Value = $allState }
        & $deferGuardReset { $script:SbSyncingEditions = $false }
    }

    $applyEditionCheck = {
        # The one place that actually mutates $script:SbCtx.SelectedKeys in
        # response to an edition (or "All") being checked/unchecked -
        # shared between the real CellContentClick handler below and
        # $setEditionChecked (the self-test's stand-in for a mouse click,
        # since DataGridView has no CheckedListBox.SetItemChecked
        # equivalent that raises a real event to hook).
        param([int]$RowIndex, [bool]$GoFull)
        if ($null -eq $script:SbCtx) { return }
        if ($RowIndex -eq 0) {
            foreach ($r in $script:SbCtx.Rows) {
                $k = "$($r.Edition)|$($r.Code)"
                if ($GoFull) { [void]$script:SbCtx.SelectedKeys.Add($k) } else { [void]$script:SbCtx.SelectedKeys.Remove($k) }
            }
        } else {
            $ed = $script:SbEditionCodes[$RowIndex - 1]
            foreach ($code in $script:SbCtx.ByEdition[$ed]) {
                $k = "$ed|$code"
                if ($GoFull) { [void]$script:SbCtx.SelectedKeys.Add($k) } else { [void]$script:SbCtx.SelectedKeys.Remove($k) }
            }
        }
        & $refreshEditionCheckboxes
        & $syncListChecks
    }

    # Self-test stand-ins for CheckedListBox's SetItemChecked/SetSelected -
    # DataGridView has no equivalent methods that raise a real event, so
    # these call the exact same logic the real UI handlers below do.
    $setEditionChecked = { param([int]$RowIndex, [bool]$Checked) & $applyEditionCheck $RowIndex $Checked }
    $selectEditionRow   = { param([int]$RowIndex) $clbEditions.CurrentCell = $clbEditions.Rows[$RowIndex].Cells[1] }

    $syncListChecks = {
        # Cheap counterpart to $refreshList: when a check/uncheck action
        # doesn't change WHICH rows are visible (search/filters/edition
        # selection untouched), just flip .Checked on the items already in
        # $lv instead of tearing down and rebuilding every ListViewItem -
        # rebuilding all ~1000 rows on every edition-checkbox click was the
        # other big piece of "ticking an edition takes a while to update".
        if ($null -eq $script:SbCtx) { return }
        $script:SbSyncingList = $true
        foreach ($item in $lv.Items) {
            $want = $script:SbCtx.SelectedKeys.Contains([string]$item.Tag)
            if ($item.Checked -ne $want) { $item.Checked = $want }
        }
        & $deferGuardReset { $script:SbSyncingList = $false }
        & $updateStatusLabel
    }

    $refreshList = {
        if ($null -eq $script:SbCtx) { return }
        $script:SbSyncingList = $true
        $lv.BeginUpdate()
        $lv.Items.Clear()
        $q = $txtSearch.Text.Trim().ToLowerInvariant()
        # Built as a plain List and added to $lv in ONE AddRange call at the
        # end, instead of one $lv.Items.Add() per row inside the loop: each
        # .Add() is its own PowerShell-to-.NET interop call, and with up to
        # ~1000 rows that per-call overhead was the real cost behind search-
        # as-you-type lagging the whole tool on every keystroke.
        $newItems = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
        foreach ($r in $script:SbCtx.Rows) {
            if ($null -ne $script:SbFilterEdition -and $r.Edition -ne $script:SbFilterEdition) { continue }
            if ($script:SbDifficultyFilter.Count -gt 0) {
                # Difficulty's "not rated" is the ABSENCE of a tier (null,
                # or out of 1-4), not a real tier value the way Effort's 0
                # is - Format-DifficultyTier's own definition of "unrated".
                $dKey = if ($null -ne $r.Difficulty -and [int]$r.Difficulty -ge 1 -and [int]$r.Difficulty -le 4) { [string][int]$r.Difficulty } else { 'unrated' }
                if (-not $script:SbDifficultyFilter.Contains($dKey)) { continue }
            }
            if ($script:SbEffortFilter.Count -gt 0) {
                $eKey = if ($null -ne $r.Effort -and [int]$r.Effort -ge 0 -and [int]$r.Effort -le 4) { [string][int]$r.Effort } else { '0' }
                if (-not $script:SbEffortFilter.Contains($eKey)) { continue }
            }
            if ($q -ne '' -and -not (([string]$r.Title).ToLowerInvariant().Contains($q) -or ([string]$r.Artist).ToLowerInvariant().Contains($q) -or $r.Code.ToLowerInvariant().Contains($q))) { continue }
            # Same "Edition|Code" key computed once and reused for both the
            # $script:SbFieldCache lookup (see $computeFieldCache) and the
            # Tag/Checked lookups below, instead of building it twice.
            $key = "$($r.Edition)|$($r.Code)"
            $rowCache = $script:SbFieldCache[$key]
            # A bare `foreach(...) { ... }` used as a value (not `.Add()`ed
            # to anything) collects its output into an array via the
            # PowerShell engine directly - measured as a real, significant
            # win over `New-Object System.Collections.Generic.List[string]`
            # + a loop of `.Add()` calls + `.ToArray()`, which profiling
            # traced as most of this loop's cost: `New-Object` with a
            # generic -TypeName re-resolves that type on every single call,
            # and with up to ~1000 rows that's ~1000 avoidable type
            # resolutions for a 5-element array each time.
            $values = foreach ($k in $script:SbVisibleFieldKeys) { $rowCache[$k] }
            # ListViewItem(string[]) takes every subitem's text in one call
            # instead of one .SubItems.Add() interop call per field -
            # ::new(), not New-Object $ctor($array): New-Object's
            # -ArgumentList unrolls a single array argument into one
            # constructor argument per element (the exact bug documented
            # elsewhere in this file for HashSet::new()), which would try to
            # match a same-arity string-by-string overload instead of the
            # intended string[] one. ::new() uses normal .NET overload
            # resolution and binds the array as the single array parameter,
            # no unrolling.
            $item = [System.Windows.Forms.ListViewItem]::new([string[]]$values)
            if ($r.IsUnknown) { $item.Name = 'unknown' }
            $item.Tag = $key
            $item.Checked = $script:SbCtx.SelectedKeys.Contains($key)
            $newItems.Add($item)
        }
        $lv.Items.AddRange($newItems.ToArray())
        $lv.Sort()
        $lv.EndUpdate()
        & $deferGuardReset { $script:SbSyncingList = $false }
        & $updateStatusLabel
    }

    $populateFromCatalog = {
        param($catalog)
        $script:SbCatalog = $catalog
        if ($SeedFromDisk) {
            $seed = Get-LocalSongSelection -GamePath $script:Cfg.GamePath -Catalog $catalog
            $script:SbCtx = Initialize-SongSelectionContext -Catalog $catalog -CurrentEditions $seed.Editions -CurrentSongFilters $seed.SongFilters
        } else {
            $script:SbCtx = Initialize-SongSelectionContext -Catalog $catalog -CurrentEditions $script:Cfg.Editions -CurrentSongFilters $script:Cfg.SongFilters
        }
        # .Invoke(), not '&' - $computeFieldCache itself is only side-
        # effecting (populates $script:SbFieldCache, returns nothing
        # useful), but '&' still carries the same real per-call pipeline
        # overhead documented on its own inner dispatch, over up to ~1000
        # rows.
        foreach ($r in $script:SbCtx.Rows) { $computeFieldCache.Invoke($r) }
        $script:SbEditionCodes = @($script:SbCtx.CatalogEditions)
        $script:SbFilterEdition = $null

        $clbEditions.Rows.Clear()
        [void]$clbEditions.Rows.Add([System.Windows.Forms.CheckState]::Unchecked, '')
        foreach ($ed in $script:SbEditionCodes) { [void]$clbEditions.Rows.Add([System.Windows.Forms.CheckState]::Unchecked, (Format-EditionDisplay $ed)) }
        & $refreshEditionCheckboxes
        & $selectEditionRow 0

        & $refreshList
        & $updateSortArrows
        foreach ($c in @($txtSearch, $btnDifficulty, $btnEffort, $clbEditions, $btnColumns, $btnCheckShown, $btnUncheckShown, $btnOk)) { $c.Enabled = $true }
        $barLoading.Visible = $false
        $lv.Visible = $true
    }

    $clbEditions.Add_CellContentClick({
        # Column 0's checkbox cell is ReadOnly + the grid is EditMode =
        # EditProgrammatically, so WinForms never toggles the value itself
        # on a click - the cell's Value going in here is guaranteed to
        # still be the PRE-click state. That makes the state decision fully
        # deterministic (no dependency on knowing what order a native
        # ThreeState column would otherwise cycle Unchecked/
        # Indeterminate/Checked through on click): currently-Checked always
        # goes to Unchecked (deselect the whole edition), anything else
        # (Unchecked or a partial-selection Indeterminate) always goes to
        # fully Checked (select the whole edition).
        param($s, $e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0) { return }
        if ($script:SbSyncingEditions -or $null -eq $script:SbCtx) { return }
        $cur = $clbEditions.Rows[$e.RowIndex].Cells[0].Value
        $goFull = ($cur -ne [System.Windows.Forms.CheckState]::Checked)
        & $applyEditionCheck $e.RowIndex $goFull
    })

    $clbEditions.Add_RowEnter({
        # RowEnter, not SelectionChanged: confirmed by an isolated test
        # script that reading $clbEditions.CurrentRow.Index INSIDE a
        # SelectionChanged handler returns the row being left, not the row
        # being entered (it only catches up after that DoEvents cycle ends)
        # - using it here silently filtered by the PREVIOUS edition/"All"
        # instead of the one just clicked, a real one-click-behind bug.
        # RowEnter's own $e.RowIndex is the new row immediately, correctly,
        # with no such lag.
        #
        # Fires on a click anywhere in a row, checkbox cell included (the
        # checkbox click above both toggles the edition AND moves here,
        # same as it did on the old CheckedListBox) - clicking "All" shows
        # the full flat list, clicking an edition narrows it to just that
        # edition's songs. Doesn't change any checked state itself.
        #
        # Unlike CheckedListBox, DataGridView does NOT refire this just
        # because a cell's Value/text was reassigned elsewhere ($row.Selected
        # and $row.Cells[i].Value are independent state on this control) -
        # the reentrant-SelectedIndexChanged bug that made every edition
        # checkbox tick silently trigger a full $refreshList rebuild
        # (~1.6s/click) cannot recur here. $script:SbSyncingEditions is
        # still checked anyway, as cheap insurance.
        param($s, $e)
        if ($e.RowIndex -lt 0 -or $script:SbSyncingEditions -or $null -eq $script:SbCtx) { return }
        $script:SbFilterEdition = if ($e.RowIndex -eq 0) { $null } else { $script:SbEditionCodes[$e.RowIndex - 1] }
        & $refreshList
    })

    $lv.Add_ItemChecked({
        param($s, $e)
        if ($script:SbSyncingList -or $null -eq $script:SbCtx) { return }
        $key = [string]$e.Item.Tag
        if ($e.Item.Checked) { [void]$script:SbCtx.SelectedKeys.Add($key) } else { [void]$script:SbCtx.SelectedKeys.Remove($key) }
        & $refreshEditionCheckboxes
        & $updateStatusLabel
    })

    $updateSortArrows = {
        # Real header-control sort glyphs (see the Native/HDITEM Add-Type
        # above) instead of appending " ^"/" v" text to the column caption -
        # Windows already draws this, WinForms just doesn't expose it.
        for ($i = 0; $i -lt $lv.Columns.Count; $i++) {
            $direction = if ($i -ne $script:SbSort.Column) { 0 } elseif ($script:SbSort.Ascending) { 1 } else { -1 }
            [LegacyDownloader.Native]::SetSortArrow($lv.Handle, $i, $direction)
        }
    }

    $lv.Add_ColumnClick({
        param($s, $e)
        if ($script:SbSort.Column -eq $e.Column) { $script:SbSort.Ascending = -not $script:SbSort.Ascending }
        else { $script:SbSort.Column = $e.Column; $script:SbSort.Ascending = $true }
        $sorter.Column = $script:SbSort.Column
        $sorter.Ascending = $script:SbSort.Ascending
        & $updateSortArrows
        $lv.Sort()
    })

    # Debounced: without this, EVERY keystroke ran a full $refreshList
    # (rebuilding up to ~1000 ListViewItems) synchronously on the UI
    # thread, which is exactly what made typing in the search box lag the
    # whole tool. Resetting a short timer on each keystroke and only
    # actually refreshing once typing pauses is the standard fix for
    # search-as-you-type over a non-trivial-cost list.
    $searchDebounceTimer = New-Object System.Windows.Forms.Timer
    $searchDebounceTimer.Interval = 250
    $searchDebounceTimer.Add_Tick({
        param($s, $e)
        $searchDebounceTimer.Stop()
        & $refreshList
    })
    $txtSearch.Add_TextChanged({
        param($s, $e)
        $searchDebounceTimer.Stop()
        $searchDebounceTimer.Start()
    })

    $btnCheckShown.Add_Click({
        param($s, $e)
        if ($null -eq $script:SbCtx) { return }
        foreach ($item in $lv.Items) { [void]$script:SbCtx.SelectedKeys.Add([string]$item.Tag) }
        & $refreshEditionCheckboxes
        & $syncListChecks
    })
    $btnUncheckShown.Add_Click({
        param($s, $e)
        if ($null -eq $script:SbCtx) { return }
        foreach ($item in $lv.Items) { [void]$script:SbCtx.SelectedKeys.Remove([string]$item.Tag) }
        & $refreshEditionCheckboxes
        & $syncListChecks
    })

    $btnOk.Add_Click({
        param($s, $e)
        if ($null -eq $script:SbCtx -or $script:SbCtx.SelectedKeys.Count -eq 0) {
            Warn-Box (T 'gui.songbrowser_none_selected_body') (T 'gui.err_title')
            return
        }
        $f.Tag = 'ok'; $f.Close()
    })
    $btnCancel.Add_Click({ param($s, $e) $f.Tag = ''; $f.Close() })
    $f.AcceptButton = $btnOk
    $f.CancelButton = $btnCancel

    $script:SbRemoteMap = $null
    $applyUnknownSongs = {
        # Merges share-only songs (present in the actual live share, absent
        # from the community sheet) into the already-loaded catalog context.
        # Scoped to editions the sheet already covers - an edition missing
        # from the sheet ENTIRELY would need its own new clbEditions row,
        # and that's a bigger structural change than "this edition has one
        # extra unmapped song".
        #
        # Can be called from either background job's completion handler,
        # whichever finishes second - it's a no-op until BOTH the catalog
        # ($script:SbCtx) and the remote listing ($script:SbRemoteMap) are
        # ready, so calling it early from the faster of the two is safe.
        if ($null -eq $script:SbCtx -or $null -eq $script:SbRemoteMap) { return }
        $newRows = New-Object System.Collections.Generic.List[object]
        foreach ($ed in $script:SbCtx.CatalogEditions) {
            if (-not $script:SbRemoteMap.Contains($ed)) { continue }
            # ::new(), not New-Object: New-Object unrolls an array argument
            # into one constructor argument per element instead of binding
            # it to the single IEnumerable<T> parameter, and throws "Cannot
            # find an overload... argument count: <N>" as a result.
            #
            # OrdinalIgnoreCase, not the default comparer: Ven found a real
            # case, edition 2's sheet codename "firework" vs. the actual
            # share file "Firework_pc.ipk" - a case-sensitive match treated
            # that as a brand new, unmapped song and showed a spurious
            # second "Firework" row alongside the real "Firework — Katy
            # Perry" one from the sheet. An evaluation pass against the
            # live share found exactly one such case-only mismatch across
            # the whole catalog (this one) plus 18 genuinely unmatched
            # files with no sheet entry at all in any casing - those 18
            # are correctly still real share-only rows; only the
            # comparison needed to stop being case-sensitive. This matches
            # the convention Get-SongIncludeArgs already uses elsewhere
            # (lowercases + rclone --ignore-case) - codenames are meant to
            # be compared case-insensitively throughout this codebase.
            $existing = [System.Collections.Generic.HashSet[string]]::new([string[]]$script:SbCtx.ByEdition[$ed], [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($code in $script:SbRemoteMap[$ed]) {
                if ($existing.Contains($code)) { continue }
                [void]$existing.Add($code)
                [void]$script:SbCtx.ByEdition[$ed].Add($code)
                # Title/Artist/Difficulty/Effort stay $null on purpose - the
                # Title field falls back to the code, and Artist/Difficulty/
                # Effort's formatters render blank (not "Not rated") for
                # IsUnknown rows, since "not rated" is itself sheet data we
                # don't have here.
                $newRow = [PSCustomObject]@{ Edition = $ed; Code = $code; Title = $null; Artist = $null; Difficulty = $null; Effort = $null; IsUnknown = $true }
                $computeFieldCache.Invoke($newRow)
                $newRows.Add($newRow)
            }
        }
        if ($newRows.Count -eq 0) { return }
        # Not "@($script:SbCtx.Rows) + @($newRows)" - PowerShell's array +
        # operator throws "Argument types do not match" here (Rows' element
        # type and a fresh [PSCustomObject][] apparently aren't compatible
        # enough for it), so build the combined array through a List
        # instead, which has no such restriction.
        $combinedRows = [System.Collections.Generic.List[object]]::new()
        $combinedRows.AddRange([object[]]$script:SbCtx.Rows)
        $combinedRows.AddRange([object[]]$newRows)
        $script:SbCtx.Rows = $combinedRows.ToArray()
        & $refreshEditionCheckboxes
        & $refreshList
    }

    # --- background catalog fetch, same Start-Job + Timer pattern as the
    # main window's Begin-Scan/Poll-Scan, so the dialog shows immediately
    # instead of blocking on the network fetch first. A second job lists
    # what's actually on the share per edition (rclone lsf, same as a real
    # update-scan) so $applyUnknownSongs above has something to diff
    # against - independent of and parallel to the catalog fetch, since
    # neither needs the other to start. ---
    $scanOut = [System.IO.Path]::GetTempFileName()
    $scanJob = Start-Job -ScriptBlock {
        param($mod, $dir, $lang, $outFile)
        Import-Module $mod -DisableNameChecking
        $null = Initialize-LegacyCore -ScriptDir $dir
        $null = Initialize-Language -Code $lang
        $catalog = Get-SongCatalog
        $catalog | Export-Clixml -Path $outFile
    } -ArgumentList $script:ModPath, $script:AppDir, (Get-LanguageCode), $scanOut

    # $script:SbRemoteMapCache/-CacheTime are declared OUTSIDE this function
    # (top of the script) so they survive across separate calls to
    # Show-SongBrowserDialog within the same running app - without this,
    # every single time the picker was opened re-ran a full ~24-edition
    # rclone scan (one rclone.exe process spawn + WebDAV round trip per
    # edition) from scratch, which is real, repeated load on both the
    # share and the machine and was very likely why the dialog kept
    # feeling slow to open even after the earlier per-click bug was fixed.
    $unknownOut = [System.IO.Path]::GetTempFileName()
    $useCache = ($null -ne $script:SbRemoteMapCache -and $null -ne $script:SbRemoteMapCacheTime -and
                 ((Get-Date) - $script:SbRemoteMapCacheTime) -lt $script:SbRemoteMapCacheTtl)
    if ($useCache) {
        $script:SbRemoteMap = $script:SbRemoteMapCache
        $script:SbCatalogJobDone = $false
        $script:SbUnknownJobDone = $true
        $unknownJob = $null
    } else {
        $unknownJob = Start-Job -ScriptBlock {
            param($mod, $dir, $lang, $outFile)
            Import-Module $mod -DisableNameChecking
            $null = Initialize-LegacyCore -ScriptDir $dir
            $null = Initialize-Language -Code $lang
            # Get-RemoteSongMap - ONE recursive listing instead of the old
            # one-rclone.exe-spawn-per-edition loop (~24 spawns) - see its
            # doc comment in Core.psm1 for why that was slow.
            $remoteMap = Get-RemoteSongMap
            $remoteMap | Export-Clixml -Path $outFile
        } -ArgumentList $script:ModPath, $script:AppDir, (Get-LanguageCode), $unknownOut
        $script:SbCatalogJobDone = $false
        $script:SbUnknownJobDone = $false
    }
    $loadTimer = New-Object System.Windows.Forms.Timer
    $loadTimer.Interval = 200
    $loadTimer.Add_Tick({
        param($s, $e)
        if (-not $script:SbCatalogJobDone -and $scanJob.State -ne 'Running' -and $scanJob.State -ne 'NotStarted') {
            $script:SbCatalogJobDone = $true
            $errMsg = $null
            try { Receive-Job $scanJob -ErrorAction Stop | Out-Null } catch { $errMsg = $_.Exception.Message }
            Remove-Job $scanJob -Force -ErrorAction SilentlyContinue
            $catalog = @()
            if (-not $errMsg) {
                try { if (Test-Path -LiteralPath $scanOut) { $catalog = @(Import-Clixml -LiteralPath $scanOut) } } catch { $errMsg = $_.Exception.Message }
            }
            Remove-Item -LiteralPath $scanOut -Force -ErrorAction SilentlyContinue
            if ($catalog.Count -eq 0) {
                $lblStatus.Text = T 'gui.songbrowser_load_failed_body'
                $barLoading.Visible = $false
            } else {
                & $populateFromCatalog $catalog
                & $applyUnknownSongs
            }
        }
        if (-not $script:SbUnknownJobDone -and $null -ne $unknownJob -and $unknownJob.State -ne 'Running' -and $unknownJob.State -ne 'NotStarted') {
            $script:SbUnknownJobDone = $true
            $errMsg = $null
            try { Receive-Job $unknownJob -ErrorAction Stop | Out-Null } catch { $errMsg = $_.Exception.Message }
            Remove-Job $unknownJob -Force -ErrorAction SilentlyContinue
            if (-not $errMsg) {
                try {
                    if (Test-Path -LiteralPath $unknownOut) {
                        $script:SbRemoteMap = Import-Clixml -LiteralPath $unknownOut
                        $script:SbRemoteMapCache = $script:SbRemoteMap
                        $script:SbRemoteMapCacheTime = Get-Date
                    }
                } catch { }
            }
            Remove-Item -LiteralPath $unknownOut -Force -ErrorAction SilentlyContinue
            & $applyUnknownSongs
            # $applyUnknownSongs only refreshes the status label as a side
            # effect of finding new rows to add - call it directly too, so
            # the "(scanning...)" note clears even when the share had
            # nothing extra (sheet fully up to date for every edition).
            & $updateStatusLabel
        }
        if ($script:SbCatalogJobDone -and $script:SbUnknownJobDone) { $loadTimer.Stop() }
    })
    $loadTimer.Start()

    $f.Add_FormClosing({
        param($s, $e)
        $loadTimer.Stop()
        $searchDebounceTimer.Stop()
        foreach ($j in @($scanJob, $unknownJob)) {
            if ($null -ne $j -and $j.State -eq 'Running') { Stop-Job $j -ErrorAction SilentlyContinue }
            if ($null -ne $j) { Remove-Job $j -Force -ErrorAction SilentlyContinue }
        }
    })

    if ($env:LEGACY_GUI_SELFTEST) {
        $f.Show()
        $waited = 0
        while ($null -eq $script:SbCtx -and $waited -lt 20000) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
            $waited += 100
        }
        if ($null -eq $script:SbCtx) {
            Write-Host "  SELFTEST WARNING: catalog never loaded within 20s (network issue?)" -ForegroundColor Yellow
        } else {
            Write-Host "  editions listed: $($script:SbEditionCodes.Count)  rows: $($lv.Items.Count)"
            Write-Host "  unknown-songs scan done yet: $script:SbUnknownJobDone; status label shows 'still checking': $($lblStatus.Text -like '*still checking*')"
            [System.Windows.Forms.Application]::DoEvents()
            $txtSearch.Text = 'psycho'
            # Search is debounced (250ms) now - a bare DoEvents() right
            # after setting .Text would check the list before the
            # debounce timer even fires.
            Start-Sleep -Milliseconds 350
            [System.Windows.Forms.Application]::DoEvents()
            $hit = @($lv.Items | Where-Object { $_.Text -match 'Psycho' })
            Write-Host "  search 'psycho' rendered $($lv.Items.Count) row(s) with no exception, matched: $(($hit | ForEach-Object { $_.Text }) -join '; ')"
            $clearBtnShownWithText = $btnClearSearch.Visible
            $txtSearch.Text = ''
            [System.Windows.Forms.Application]::DoEvents()
            $clearBtnHiddenWhenEmpty = -not $btnClearSearch.Visible
            Write-Host "  clear-search button visible with text: $clearBtnShownWithText, hidden once cleared: $clearBtnHiddenWhenEmpty"
            $script:SbSort.Column = 1
            $script:SbSort.Ascending = $true
            $sorter.Column = 1
            $sorter.Ascending = $true
            try {
                & $updateSortArrows
                $lv.Sort()
                [System.Windows.Forms.Application]::DoEvents()
                Write-Host "  list sort + native sort-arrow update rendered with no exception"
            } catch {
                Write-Host "  SELFTEST FAILURE: sort arrow P/Invoke threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            $txtSearch.Text = ''
            Start-Sleep -Milliseconds 350
            [System.Windows.Forms.Application]::DoEvents()

            # Real mouse interaction with the picker was exactly the gap the
            # previous version of this self-test left uncovered, and exactly
            # where the "Error creating window handle" crash was hiding
            # (ListViewGroup.Header mutated from inside the ListView's own
            # ItemChecked handler). Drive the same code paths a real click
            # would, via .Checked/.SetItemChecked/.SetSelected (these raise
            # the same ItemChecked/ItemCheck/SelectedIndexChanged events a
            # mouse click does), so this regresses loudly instead of only
            # surfacing in Ven's hands again.
            try {
                $before = $script:SbCtx.SelectedKeys.Count
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $lv.Items[0].Checked = -not $lv.Items[0].Checked
                [System.Windows.Forms.Application]::DoEvents()
                $sw.Stop()
                Write-Host "  ticking a song's checkbox took $($sw.ElapsedMilliseconds) ms with no exception (selected: $before -> $($script:SbCtx.SelectedKeys.Count))"
            } catch {
                Write-Host "  SELFTEST FAILURE: ticking a song's checkbox threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                & $setEditionChecked 1 $true
                [System.Windows.Forms.Application]::DoEvents()
                $sw.Stop()
                Write-Host "  ticking an edition's checkbox took $($sw.ElapsedMilliseconds) ms with no exception"
                & $setEditionChecked 1 $false
                [System.Windows.Forms.Application]::DoEvents()
            } catch {
                Write-Host "  SELFTEST FAILURE: ticking an edition's checkbox threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            try {
                $sw1 = [System.Diagnostics.Stopwatch]::StartNew()
                & $selectEditionRow 1
                [System.Windows.Forms.Application]::DoEvents()
                $sw1.Stop()
                $filteredCount = $lv.Items.Count
                $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
                & $selectEditionRow 0
                [System.Windows.Forms.Application]::DoEvents()
                $sw2.Stop()
                Write-Host "  selecting edition #1 ($($sw1.ElapsedMilliseconds) ms) filtered the list to $filteredCount row(s); reselecting All ($($sw2.ElapsedMilliseconds) ms) restored $($lv.Items.Count) row(s)"
            } catch {
                Write-Host "  SELFTEST FAILURE: edition filter click threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            try {
                # Partial-selection glyph: select roughly half an edition's
                # songs directly, confirm the checkbox reports Indeterminate
                # (not just a text suffix), then simulate a real click on it
                # ($setEditionChecked is what a mouse click on the glyph
                # drives internally, via $applyEditionCheck) and confirm it
                # lands on a clean "select all", not stuck cycling through
                # the third state.
                $partialEd = $script:SbEditionCodes[0]
                $partialCodes = @($script:SbCtx.ByEdition[$partialEd])
                $half = [Math]::Max(1, [Math]::Floor($partialCodes.Count / 2))
                foreach ($code in $partialCodes[0..($half - 1)]) { [void]$script:SbCtx.SelectedKeys.Add("$partialEd|$code") }
                foreach ($code in $partialCodes[$half..($partialCodes.Count - 1)]) { [void]$script:SbCtx.SelectedKeys.Remove("$partialEd|$code") }
                & $refreshEditionCheckboxes
                [System.Windows.Forms.Application]::DoEvents()
                $stateWhilePartial = $clbEditions.Rows[1].Cells[0].Value
                & $setEditionChecked 1 $true
                [System.Windows.Forms.Application]::DoEvents()
                $allSelectedAfterClick = (@($partialCodes | Where-Object { $script:SbCtx.SelectedKeys.Contains("$partialEd|$_") }).Count -eq $partialCodes.Count)
                Write-Host "  partial edition selection shows $stateWhilePartial; clicking it selected everything: $allSelectedAfterClick"
            } catch {
                Write-Host "  SELFTEST FAILURE: partial-selection checkbox state threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            try {
                & $applyDifficultyFilterToggle 0 $true
                [System.Windows.Forms.Application]::DoEvents()
                $unratedShown = $lv.Items.Count
                $diffColIdx = [Array]::IndexOf($script:SbVisibleFieldKeys, 'Difficulty')
                # A share-only row can be merged in and match this same
                # "not rated" filter (it has no Difficulty data either) but
                # renders blank rather than the literal "Not rated" text
                # (that string is real sheet data those rows don't have,
                # see $fieldByKey.Difficulty.Value above) - both count as
                # correctly filtered. With Get-RemoteSongMap's real scan now
                # fast enough to sometimes finish DURING self-test (it used
                # to reliably still be running at this point), this can
                # actually happen here now, not just in principle.
                $allUnrated = @($lv.Items | Where-Object { $_.SubItems[$diffColIdx].Text -ne 'Not rated' -and $_.SubItems[$diffColIdx].Text -ne '' }).Count -eq 0
                & $applyDifficultyFilterToggle 1 $true
                [System.Windows.Forms.Application]::DoEvents()
                $unratedOrEasyShown = $lv.Items.Count
                $btnDiffTextAfterTwo = $btnDifficulty.Text
                & $applyDifficultyFilterToggle 0 $false
                & $applyDifficultyFilterToggle 1 $false
                [System.Windows.Forms.Application]::DoEvents()
                Write-Host "  'Not rated' difficulty filter showed $unratedShown row(s), all unrated: $allUnrated"
                Write-Host "  adding 'Easy' to the filter (multi-select) widened it to $unratedOrEasyShown row(s), button text: '$btnDiffTextAfterTwo'"
            } catch {
                Write-Host "  SELFTEST FAILURE: multi-select difficulty filter threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            try {
                $fullColumnCount = $lv.Columns.Count
                $columnMenuItems['Artist'].Checked = -not (& $toggleColumnVisibility 'Artist' $false)
                [System.Windows.Forms.Application]::DoEvents()
                $hiddenColumnCount = $lv.Columns.Count
                $firstRowFieldCount = $lv.Items[0].SubItems.Count
                $columnMenuItems['Artist'].Checked = (& $toggleColumnVisibility 'Artist' $true)
                [System.Windows.Forms.Application]::DoEvents()
                # Guard: hide everything down to the last column, then
                # confirm hiding that last one is refused rather than
                # leaving zero columns.
                foreach ($k in @($script:SbVisibleFieldKeys | Select-Object -Skip 1)) { & $toggleColumnVisibility $k $false }
                [System.Windows.Forms.Application]::DoEvents()
                $downToOne = $script:SbVisibleFieldKeys.Count
                $lastHideRefused = -not (& $toggleColumnVisibility $script:SbVisibleFieldKeys[0] $false)
                foreach ($k in $fieldByKey.Keys) { & $toggleColumnVisibility $k $true }
                [System.Windows.Forms.Application]::DoEvents()
                Write-Host "  hiding Artist: $fullColumnCount -> $hiddenColumnCount columns (row had $firstRowFieldCount fields); re-showing restored $($lv.Columns.Count); down to $downToOne column(s), hiding the last refused: $lastHideRefused"
            } catch {
                Write-Host "  SELFTEST FAILURE: column visibility toggle threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            try {
                & $setEditionChecked 0 $true
                [System.Windows.Forms.Application]::DoEvents()
                $afterCheckAll = $script:SbCtx.SelectedKeys.Count
                & $setEditionChecked 0 $false
                [System.Windows.Forms.Application]::DoEvents()
                Write-Host "  checking All selected $afterCheckAll of $($script:SbCtx.Rows.Count); unchecking All left $($script:SbCtx.SelectedKeys.Count) selected"
            } catch {
                Write-Host "  SELFTEST FAILURE: All checkbox threw: $($_.Exception.Message)" -ForegroundColor Red
            }
            try {
                # $applyUnknownSongs's own logic, tested directly with a
                # fake remote map instead of a real rclone scan - the actual
                # network fetch ($unknownJob) can only be verified against
                # Ven's real share, but the merge/display logic that runs
                # once it returns is fully testable here.
                $testEdition = $script:SbEditionCodes[0]
                $fakeCode = 'zzz_selftest_unknown_song'
                # A real bug found in live use: a sheet codename and the
                # actual share filename differing only by case (Ven found
                # edition 2's sheet "firework" vs. the real share file
                # "Firework_pc.ipk") used to be treated as a brand new,
                # unmapped song and merged in as a spurious duplicate row
                # alongside the real sheet one - $existing in
                # $applyUnknownSongs was a case-SENSITIVE HashSet. Exercise
                # that exact shape here: an existing code from this
                # edition, presented back in a different case, should be
                # recognized as already-known and NOT produce a second row.
                $existingCode = @($script:SbCtx.ByEdition[$testEdition])[0]
                $caseFlipped = $existingCode.ToUpperInvariant()
                $beforeRowCount = $script:SbCtx.Rows.Count
                $script:SbRemoteMap = @{ $testEdition = @($fakeCode, $caseFlipped) }
                & $applyUnknownSongs
                [System.Windows.Forms.Application]::DoEvents()
                $afterRowCount = $script:SbCtx.Rows.Count
                $foundRow = $null -ne ($script:SbCtx.Rows | Where-Object { $_.Code -eq $fakeCode })
                $noCaseDupe = ($afterRowCount - $beforeRowCount) -eq 1
                Write-Host "  case-mismatch guard: presenting '$existingCode' back as '$caseFlipped' added no duplicate row: $noCaseDupe (rows grew by $($afterRowCount - $beforeRowCount), expected 1)"
                & $selectEditionRow 0
                $txtSearch.Text = $fakeCode
                Start-Sleep -Milliseconds 350
                [System.Windows.Forms.Application]::DoEvents()
                $shownItem = if ($lv.Items.Count -eq 1) { $lv.Items[0] } else { $null }
                # Looked up by current position in $script:SbVisibleFieldKeys
                # rather than a hardcoded SubItems index - column order is
                # now user-changeable (default order, reorder-by-drag, and
                # show/hide can all move a field to a different index).
                $titleIdx = [Array]::IndexOf($script:SbVisibleFieldKeys, 'Title')
                $artistIdx = [Array]::IndexOf($script:SbVisibleFieldKeys, 'Artist')
                $diffIdx = [Array]::IndexOf($script:SbVisibleFieldKeys, 'Difficulty')
                $codenameShown = ($null -ne $shownItem -and $shownItem.SubItems[[Array]::IndexOf($script:SbVisibleFieldKeys, 'Code')].Text -eq $fakeCode)
                $titleShowsEditionAndFile = ($null -ne $shownItem -and $shownItem.SubItems[$titleIdx].Text -eq "$testEdition/${fakeCode}_pc.ipk")
                $artistBlank = ($null -ne $shownItem -and [string]::IsNullOrEmpty($shownItem.SubItems[$artistIdx].Text))
                $diffBlank = ($null -ne $shownItem -and [string]::IsNullOrEmpty($shownItem.SubItems[$diffIdx].Text))
                $sortedFirst = ($lv.Items.Count -gt 0 -and $lv.Items[0].Name -eq 'unknown')
                if ($null -ne $shownItem) { $shownItem.Checked = $true; [System.Windows.Forms.Application]::DoEvents() }
                $selectable = $script:SbCtx.SelectedKeys.Contains("$testEdition|$fakeCode")
                $txtSearch.Text = ''
                Start-Sleep -Milliseconds 350
                [System.Windows.Forms.Application]::DoEvents()
                Write-Host "  share-only song merge: rows $beforeRowCount -> $afterRowCount, found: $foundRow, codename shown: $codenameShown, title shows edition/file: $titleShowsEditionAndFile, artist blank: $artistBlank, difficulty blank: $diffBlank, sorts first: $sortedFirst, selectable: $selectable"
            } catch {
                Write-Host "  SELFTEST FAILURE: share-only song merge threw: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        $f.Close()
        $f.Dispose()
        return $null
    }

    $f.ShowDialog($script:Form) | Out-Null

    $ret = $null
    if ($f.Tag -eq 'ok') {
        $ret = Resolve-SongSelection -Context $script:SbCtx -SelectedKeys $script:SbCtx.SelectedKeys
        if ($null -ne $ret) { $ret.Catalog = $script:SbCatalog }
    }
    $f.Dispose()
    return $ret
}

# ===========================================================================
# first-run setup
# ===========================================================================

function Run-SetupDialog {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'gui.setup_title'
    $f.Font = $script:FontBase
    $f.BackColor = $script:ColorBg
    $f.ForeColor = $script:ColorText
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $f.ClientSize = New-Object System.Drawing.Size(460, 260)
    $f.MinimizeBox = $false; $f.MaximizeBox = $false

    # Top right language selector
    $lblLang = New-Label (T 'gui.lang_label') 200 14 70 24
    $lblLang.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $lblLang.ForeColor = $script:ColorMuted

    $cmbLang = New-Object System.Windows.Forms.ComboBox
    $cmbLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbLang.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $cmbLang.ItemHeight = 22
    $cmbLang.Font = $script:FontBase
    $cmbLang.SetBounds(276, 12, 168, 26)
    $cmbLang.BackColor = $script:ColorCard
    $cmbLang.ForeColor = $script:ColorText

    $cmbLang.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0 -or $e.Index -ge $script:Langs.Count) { return }
        $e.DrawBackground()

        $lang = $script:Langs[$e.Index]
        $bmp = Get-FlagBitmap $lang.Code

        $flagX = $e.Bounds.X + 6
        $flagY = $e.Bounds.Y + [Math]::Max(0, [int](($e.Bounds.Height - 15) / 2))
        if ($null -ne $bmp) {
            $e.Graphics.DrawImage($bmp, $flagX, $flagY, 20, 15)
            $borderPen = [System.Drawing.Pens]::LightGray
            $e.Graphics.DrawRectangle($borderPen, $flagX - 1, $flagY - 1, 21, 16)
        }

        $textX = $flagX + 28
        $textBounds = New-Object System.Drawing.RectangleF($textX, $e.Bounds.Y, ($e.Bounds.Width - $textX), $e.Bounds.Height)
        $brush = if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) {
            New-Object System.Drawing.SolidBrush([System.Drawing.SystemColors]::HighlightText)
        } else {
            New-Object System.Drawing.SolidBrush($script:ColorText)
        }
        $sf = New-Object System.Drawing.StringFormat
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $sf.Alignment = [System.Drawing.StringAlignment]::Near

        $e.Graphics.DrawString($lang.NativeName, $e.Font, $brush, $textBounds, $sf)
        $brush.Dispose()
        $sf.Dispose()
        $e.DrawFocusRectangle()
    })

    foreach ($l in $script:Langs) { [void]$cmbLang.Items.Add($l.NativeName) }
    for ($i = 0; $i -lt $script:Langs.Count; $i++) {
        if ($script:Langs[$i].Code -eq $script:Cfg.Lang) { $cmbLang.SelectedIndex = $i; break }
    }
    if ($cmbLang.SelectedIndex -lt 0 -and $cmbLang.Items.Count -gt 0) { $cmbLang.SelectedIndex = 0 }

    $lbl = New-Label (T 'gui.setup_body') 18 48 424 100
    $bHave = New-Btn (T 'gui.setup_have') 18 168 206 38 $false
    $bGet  = New-Btn (T 'gui.setup_get') 236 168 206 38 $true

    $lnkTutorial = New-Object System.Windows.Forms.LinkLabel
    $lnkTutorial.Text = T 'gui.tutorial_link'
    $lnkTutorial.Font = $script:FontBase
    $lnkTutorial.LinkColor = $script:ColorPrimary
    $lnkTutorial.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lnkTutorial.SetBounds(18, 216, 424, 22)

    $reapplySetupLang = {
        $f.Text          = T 'gui.setup_title'
        $lblLang.Text    = T 'gui.lang_label'
        $lbl.Text        = T 'gui.setup_body'
        $bHave.Text      = T 'gui.setup_have'
        $bGet.Text       = T 'gui.setup_get'
        $lnkTutorial.Text = T 'gui.tutorial_link'
    }

    $cmbLang.Add_SelectedIndexChanged({
        param($s, $e)
        $idx = $cmbLang.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:Langs.Count) {
            $code = $script:Langs[$idx].Code
            if ($code -ne $script:Cfg.Lang) {
                $null = Initialize-Language -Code $code
                Save-Config -GamePath $script:Cfg.GamePath -Editions $script:Cfg.Editions -Lang $code
                $script:Cfg = Load-Config
                & $reapplySetupLang
            }
        }
    })

    $bHave.Add_Click({ param($s, $e) $f.Tag = 'have'; $f.Close() })
    $bGet.Add_Click({ param($s, $e) $f.Tag = 'get'; $f.Close() })
    $lnkTutorial.Add_LinkClicked({
        param($s, $e)
        $url = Get-TutorialUrl (Get-LanguageCode)
        try {
            Start-Process $url | Out-Null
        } catch {
            Info-Box (T 'gui.tutorial_open_failed' @{ url = $url }) (T 'gui.err_title')
        }
    })
    $f.Controls.AddRange(@($lblLang, $cmbLang, $lbl, $bHave, $bGet, $lnkTutorial))
    $f.ShowDialog() | Out-Null
    $mode = [string]$f.Tag
    $f.Dispose()
    if ($mode -ne 'have' -and $mode -ne 'get') { return }

    $desc = if ($mode -eq 'have') { T 'gui.setup_pick_have' } else { T 'gui.setup_pick_new' }
    $path = Pick-Folder $desc
    if (-not $path) { return }
    if ($mode -eq 'get') {
        try { [System.IO.Directory]::CreateDirectory($path) | Out-Null } catch {
            Warn-Box (T 'error.cant_create_folder' @{ error = $_.Exception.Message }) (T 'gui.err_title'); return
        }
    }
    Save-Config -GamePath $path -Editions $script:Cfg.Editions -Lang $script:Cfg.Lang
    $script:Cfg = Load-Config
    return $mode   # 'have' or 'get' - the caller auto-starts a check after "get"
}

# ===========================================================================
# main window
# ===========================================================================

function Refresh-FolderStatus {
    $gp = $script:Cfg.GamePath
    if ($null -ne $script:TxtFolder) { $script:TxtFolder.Text = $gp }
    if ([string]::IsNullOrWhiteSpace($gp)) {
        $script:LblFolder.Text = T 'gui.folder_unset'
        $script:LblFolder.ForeColor = [System.Drawing.Color]::Firebrick
    } elseif (Test-GameFolder $gp) {
        $script:LblFolder.Text = T 'gui.folder_ok' @{ songs = (Get-LocalSongCount $gp) }
        $script:LblFolder.ForeColor = [System.Drawing.Color]::FromArgb(22, 120, 60)
    } else {
        $script:LblFolder.Text = T 'gui.folder_missing'
        $script:LblFolder.ForeColor = [System.Drawing.Color]::FromArgb(180, 110, 15)
    }
}

function Show-TrackedViewDialog {
    # Read-only reconciliation view opened by the main window's "View
    # tracked" button (only enabled in Specific mode with something
    # tracked): shows every song that's either tracked (per config) or
    # actually downloaded, color-coded by which is true - Green (both),
    # Yellow (tracked, not downloaded yet), Red (downloaded, not/no longer
    # tracked). Deliberately built to look and behave like
    # Show-SongBrowserDialog (same column set incl. Columns... visibility,
    # same Difficulty/Effort filter dropdowns, same search box, same native
    # sort arrows) - the only differences are no checkboxes anywhere (this
    # is a viewer, not a picker: no Check/Uncheck-shown buttons, no OK/Save,
    # a plain non-interactive editions list instead of clbEditions's
    # checkbox column) and the added row-color status coding. It does NOT
    # reuse Show-SongBrowserDialog's own code, though: that function's
    # actual bulk is a tightly-coupled checkbox/tri-state-selection state
    # machine (SelectedKeys mutation, edition Indeterminate logic, OK-button
    # enablement) that has nothing to do with a read-only view and would
    # add real risk threading a mode flag through it. Uses its own $script:
    # Tv*-prefixed state so nothing here can collide with $script:Sb*
    # if both dialogs are ever open in the same session (sequentially -
    # neither is modeless).
    $catalog = @(Get-CachedSongCatalog)
    $status = Get-TrackedDownloadStatus -GamePath $script:Cfg.GamePath -Editions $script:Cfg.Editions -SongFilters $script:Cfg.SongFilters -Catalog $catalog
    $dupKeys = if ($catalog.Count -gt 0) { Get-DuplicateTitleKeys -Rows $catalog } else { $null }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'gui.trackedview_title'
    $f.Font = $script:FontBase
    $f.BackColor = $script:ColorBg
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $f.MinimizeBox = $false; $f.MaximizeBox = $true
    $f.ShowIcon = $false
    $f.ClientSize = New-Object System.Drawing.Size(1000, 648)
    $f.MinimumSize = New-Object System.Drawing.Size(860, 480)

    # ---- top row: search box + Difficulty/Effort filter dropdowns ----
    $diffTierValues = @('unrated', '1', '2', '3', '4')
    $diffTierLabels = @((Format-DifficultyTier $null), (Format-DifficultyTier 1), (Format-DifficultyTier 2), (Format-DifficultyTier 3), (Format-DifficultyTier 4))
    $effTierValues  = @('0', '1', '2', '3', '4')
    $effTierLabels  = @((Format-EffortTier 0), (Format-EffortTier 1), (Format-EffortTier 2), (Format-EffortTier 3), (Format-EffortTier 4))
    $dropdownArrowSuffix = ' ' + [char]0x25BE

    $btnEffort = New-Btn (T 'gui.songbrowser_all_efforts') 826 14 160 24 $false
    $btnEffort.Anchor = 'Top,Right'
    $btnEffort.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnDifficulty = New-Btn (T 'gui.songbrowser_all_difficulties') 658 14 160 24 $false
    $btnDifficulty.Anchor = 'Top,Right'
    $btnDifficulty.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $resizeFilterButtons = {
        $pad = 20
        $effWidth = [System.Windows.Forms.TextRenderer]::MeasureText($btnEffort.Text, $btnEffort.Font).Width + $pad
        $diffWidth = [System.Windows.Forms.TextRenderer]::MeasureText($btnDifficulty.Text, $btnDifficulty.Font).Width + $pad
        $rightEdge = 986
        $btnEffort.Width = $effWidth
        $btnEffort.Left = $rightEdge - $effWidth
        $btnDifficulty.Width = $diffWidth
        $btnDifficulty.Left = $btnEffort.Left - 8 - $diffWidth
    }
    $updateDifficultyButtonText = {
        $n = $script:TvDifficultyFilter.Count
        $btnDifficulty.Text = if ($n -eq 0) { (T 'gui.songbrowser_all_difficulties') + $dropdownArrowSuffix }
                              elseif ($n -eq 1) { $diffTierLabels[[Array]::IndexOf($diffTierValues, @($script:TvDifficultyFilter)[0])] + $dropdownArrowSuffix }
                              else { (T 'gui.songbrowser_n_selected' @{ count = $n }) + $dropdownArrowSuffix }
        & $resizeFilterButtons
    }
    $updateEffortButtonText = {
        $n = $script:TvEffortFilter.Count
        $btnEffort.Text = if ($n -eq 0) { (T 'gui.songbrowser_all_efforts') + $dropdownArrowSuffix }
                          elseif ($n -eq 1) { $effTierLabels[[Array]::IndexOf($effTierValues, @($script:TvEffortFilter)[0])] + $dropdownArrowSuffix }
                          else { (T 'gui.songbrowser_n_selected' @{ count = $n }) + $dropdownArrowSuffix }
        & $resizeFilterButtons
    }
    & $updateDifficultyButtonText
    & $updateEffortButtonText

    $diffPopup = New-FilterDropdown $diffTierLabels
    $applyDifficultyFilterToggle = {
        param([int]$Index, [bool]$Checked)
        $diffPopup.Items[$Index].Checked = $Checked
        $val = $diffTierValues[$Index]
        if ($Checked) { [void]$script:TvDifficultyFilter.Add($val) } else { [void]$script:TvDifficultyFilter.Remove($val) }
        & $updateDifficultyButtonText
        & $refreshList
    }
    $diffPopup.Menu.Add_ItemClicked({
        param($s, $e)
        $idx = $diffPopup.Items.IndexOf($e.ClickedItem)
        if ($idx -lt 0) { return }
        & $applyDifficultyFilterToggle $idx (-not $e.ClickedItem.Checked)
    })
    $btnDifficulty.Add_Click({ param($s, $e) $diffPopup.Menu.Show($btnDifficulty, (New-Object System.Drawing.Point(0, $btnDifficulty.Height))) })

    $effPopup = New-FilterDropdown $effTierLabels
    $applyEffortFilterToggle = {
        param([int]$Index, [bool]$Checked)
        $effPopup.Items[$Index].Checked = $Checked
        $val = $effTierValues[$Index]
        if ($Checked) { [void]$script:TvEffortFilter.Add($val) } else { [void]$script:TvEffortFilter.Remove($val) }
        & $updateEffortButtonText
        & $refreshList
    }
    $effPopup.Menu.Add_ItemClicked({
        param($s, $e)
        $idx = $effPopup.Items.IndexOf($e.ClickedItem)
        if ($idx -lt 0) { return }
        & $applyEffortFilterToggle $idx (-not $e.ClickedItem.Checked)
    })
    $btnEffort.Add_Click({ param($s, $e) $effPopup.Menu.Show($btnEffort, (New-Object System.Drawing.Point(0, $btnEffort.Height))) })

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.SetBounds(14, 14, 636, 24)
    $txtSearch.Anchor = 'Top,Left,Right'
    $txtSearch.Font = $script:FontBase

    $btnClearSearch = New-Object System.Windows.Forms.Button
    $btnClearSearch.Text = [string][char]0x00D7
    $btnClearSearch.Font = $script:FontBase
    $btnClearSearch.Size = New-Object System.Drawing.Size(20, 20)
    $btnClearSearch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClearSearch.FlatAppearance.BorderSize = 0
    $btnClearSearch.FlatAppearance.MouseOverBackColor = $script:ColorBg
    $btnClearSearch.FlatAppearance.MouseDownBackColor = $script:ColorBorder
    $btnClearSearch.BackColor = [System.Drawing.Color]::Transparent
    $btnClearSearch.ForeColor = $script:ColorMuted
    $btnClearSearch.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClearSearch.TabStop = $false
    $btnClearSearch.Visible = $false
    $repositionClearSearchBtn = {
        $btnClearSearch.Location = New-Object System.Drawing.Point(
            ($txtSearch.Right - $btnClearSearch.Width - 3),
            ($txtSearch.Top + [int](($txtSearch.Height - $btnClearSearch.Height) / 2)))
    }
    $txtSearch.Add_SizeChanged({ & $repositionClearSearchBtn })
    & $repositionClearSearchBtn
    $txtSearch.Add_TextChanged({ $btnClearSearch.Visible = ($txtSearch.Text.Length -gt 0) })
    $btnClearSearch.Add_Click({ param($s, $e) $txtSearch.Text = ''; $txtSearch.Focus() })

    # ---- editions list (plain names, no checkboxes - single-select filter) ----
    $lblEditions = New-Label (T 'gui.songbrowser_editions_header') 14 44 240 18
    $lblEditions.Font = $script:FontBold

    $lstEditions = New-Object System.Windows.Forms.ListBox
    $lstEditions.SetBounds(14, 66, 240, 500)
    $lstEditions.Anchor = 'Top,Left,Bottom'
    $lstEditions.Font = $script:FontBase
    $lstEditions.IntegralHeight = $false
    $lstEditions.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    # ---- song list: same data-driven column set as the picker (Columns... toggle) ----
    $fieldByKey = [ordered]@{
        Code       = @{ Header = (T 'gui.songbrowser_col_codename');   Width = 110; Value = { param($r) [string]$r.Code } }
        Title      = @{ Header = (T 'gui.songbrowser_col_title');      Width = 210; Value = { param($r) if ($r.IsUnknown) { "$($r.Edition)/$($r.Code)_pc.ipk" } elseif ([string]::IsNullOrWhiteSpace($r.Title)) { $r.Code } else { $r.Title } } }
        Artist     = @{ Header = (T 'gui.songbrowser_col_artist');     Width = 150; Value = { param($r) if ($r.IsUnknown) { '' } else { [string]$r.Artist } } }
        Difficulty = @{ Header = (T 'gui.songbrowser_col_difficulty'); Width = 80;  Value = { param($r) if ($r.IsUnknown) { '' } else { Format-DifficultyTier $r.Difficulty } } }
        Effort     = @{ Header = (T 'gui.songbrowser_col_effort');     Width = 80;  Value = { param($r) if ($r.IsUnknown) { '' } else { Format-EffortTier $r.Effort } } }
    }
    $script:TvVisibleFieldKeys = @($fieldByKey.Keys)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.SetBounds(268, 66, 718, 500)
    $lv.Anchor = 'Top,Left,Right,Bottom'
    $lv.View = [System.Windows.Forms.View]::Details
    $lv.CheckBoxes = $false
    $lv.FullRowSelect = $true
    $lv.HideSelection = $false
    $lv.MultiSelect = $false
    $lv.GridLines = $false
    $lv.AllowColumnReorder = $true
    $lv.Font = $script:FontBase
    $lv.BackColor = $script:ColorCard

    $rebuildColumns = {
        $lv.Columns.Clear()
        foreach ($key in $script:TvVisibleFieldKeys) { [void]$lv.Columns.Add($fieldByKey[$key].Header, $fieldByKey[$key].Width) }
    }
    & $rebuildColumns

    $btnColumns = New-Btn (T 'gui.songbrowser_btn_columns') 892 42 94 22 $false
    $btnColumns.Anchor = 'Top,Right'
    $btnColumns.Width = [System.Windows.Forms.TextRenderer]::MeasureText($btnColumns.Text, $btnColumns.Font).Width + 20
    $btnColumns.Left = 986 - $btnColumns.Width

    $columnMenu = New-Object System.Windows.Forms.ContextMenuStrip
    foreach ($key in $fieldByKey.Keys) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($fieldByKey[$key].Header)
        $mi.Checked = $true
        $mi.Tag = $key
        [void]$columnMenu.Items.Add($mi)
    }
    $toggleColumnVisibility = {
        param([string]$Key, [bool]$Visible)
        if (-not $Visible -and $script:TvVisibleFieldKeys.Count -le 1) { return $false }
        $keys = [System.Collections.Generic.List[string]]::new([string[]]$script:TvVisibleFieldKeys)
        if ($Visible) {
            if (-not $keys.Contains($Key)) {
                $canonicalOrder = @($fieldByKey.Keys)
                $insertAt = 0
                foreach ($k in $keys) {
                    if ([Array]::IndexOf($canonicalOrder, $k) -lt [Array]::IndexOf($canonicalOrder, $Key)) { $insertAt++ }
                }
                $keys.Insert($insertAt, $Key)
            }
        } else {
            [void]$keys.Remove($Key)
        }
        $script:TvVisibleFieldKeys = @($keys)
        & $rebuildColumns
        $script:TvSort.Column = 0; $script:TvSort.Ascending = $true
        $sorter.Column = 0; $sorter.Ascending = $true
        & $refreshList
        & $updateSortArrows
        return $true
    }
    $columnMenu.Add_ItemClicked({
        param($s, $e)
        $key = $e.ClickedItem.Tag
        if ($null -eq $key) { return }
        $newVisible = -not $e.ClickedItem.Checked
        if (& $toggleColumnVisibility $key $newVisible) { $e.ClickedItem.Checked = $newVisible }
    })
    $btnColumns.Add_Click({ param($s, $e) $columnMenu.Show($btnColumns, (New-Object System.Drawing.Point(0, $btnColumns.Height))) })

    $colorGreen  = [System.Drawing.Color]::FromArgb(224, 247, 231)
    $colorYellow = [System.Drawing.Color]::FromArgb(255, 247, 219)
    $colorRed    = [System.Drawing.Color]::FromArgb(253, 226, 226)

    $lblEmpty = New-Label (T 'gui.trackedview_empty') 268 66 718 24
    $lblEmpty.ForeColor = $script:ColorMuted
    $lblEmpty.Anchor = 'Top,Left,Right'
    $lblEmpty.Visible = ($status.Rows.Count -eq 0)

    # ---- legend + status row, above the Close button ----
    $legendItems = @(
        @{ Color = $colorGreen;  Key = 'gui.trackedview_legend_green' },
        @{ Color = $colorYellow; Key = 'gui.trackedview_legend_yellow' },
        @{ Color = $colorRed;    Key = 'gui.trackedview_legend_red' }
    )
    $legendControls = New-Object System.Collections.Generic.List[object]
    $legendY = 578
    $legendX = 14
    foreach ($item in $legendItems) {
        $swatch = New-Object System.Windows.Forms.Panel
        $swatch.SetBounds($legendX, $legendY + 3, 14, 14)
        $swatch.BackColor = $item.Color
        $swatch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $swatch.Anchor = 'Bottom,Left'
        $legendControls.Add($swatch)
        $legendX += 20
        $label = T $item.Key
        $lbl = New-Label $label $legendX $legendY 220 20
        $lbl.ForeColor = $script:ColorMuted
        $lbl.Anchor = 'Bottom,Left'
        $width = [System.Windows.Forms.TextRenderer]::MeasureText($label, $lbl.Font).Width + 6
        $lbl.Width = $width
        $legendControls.Add($lbl)
        $legendX += $width + 16
    }

    $lblStatus = New-Label '' 14 606 772 20
    $lblStatus.ForeColor = $script:ColorMuted
    $lblStatus.Anchor = 'Bottom,Left,Right'

    $btnClose = New-Btn (T 'gui.btn_close') 906 602 80 30 $true
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({ param($s, $e) $f.Close() })
    $f.CancelButton = $btnClose

    # ---- state (Tv*-prefixed - see the function's own header comment) ----
    $script:TvFilterEdition = $null
    $script:TvSort = @{ Column = 1; Ascending = $true }
    $script:TvDifficultyFilter = New-Object System.Collections.Generic.HashSet[string]
    $script:TvEffortFilter = New-Object System.Collections.Generic.HashSet[string]
    $fieldCache = @{}
    foreach ($r in $status.Rows) {
        $key = "$($r.Edition)|$($r.Code)"
        $cache = @{}
        foreach ($fk in $fieldByKey.Keys) { $cache[$fk] = (& $fieldByKey[$fk].Value $r) }
        $cache['_status'] = $r.Status
        $cache['_editionDisp'] = Format-EditionDisplay $r.Edition
        $fieldCache[$key] = $cache
    }

    $updateStatusLabel = { $lblStatus.Text = T 'gui.trackedview_status' @{ shown = $lv.Items.Count; total = $status.Rows.Count } }

    $refreshList = {
        $lv.BeginUpdate()
        $lv.Items.Clear()
        $q = $txtSearch.Text.Trim().ToLowerInvariant()
        $newItems = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
        foreach ($r in $status.Rows) {
            if ($null -ne $script:TvFilterEdition -and $r.Edition -ne $script:TvFilterEdition) { continue }
            if ($script:TvDifficultyFilter.Count -gt 0) {
                $dKey = if ($null -ne $r.Difficulty -and [int]$r.Difficulty -ge 1 -and [int]$r.Difficulty -le 4) { [string][int]$r.Difficulty } else { 'unrated' }
                if (-not $script:TvDifficultyFilter.Contains($dKey)) { continue }
            }
            if ($script:TvEffortFilter.Count -gt 0) {
                $eKey = if ($null -ne $r.Effort -and [int]$r.Effort -ge 0 -and [int]$r.Effort -le 4) { [string][int]$r.Effort } else { '0' }
                if (-not $script:TvEffortFilter.Contains($eKey)) { continue }
            }
            $key = "$($r.Edition)|$($r.Code)"
            $rowCache = $fieldCache[$key]
            if ($q -ne '' -and -not (([string]$rowCache['Title']).ToLowerInvariant().Contains($q) -or ([string]$rowCache['Artist']).ToLowerInvariant().Contains($q) -or ([string]$rowCache['Code']).ToLowerInvariant().Contains($q))) { continue }
            $values = foreach ($k in $script:TvVisibleFieldKeys) { $rowCache[$k] }
            $item = [System.Windows.Forms.ListViewItem]::new([string[]]$values)
            if ($r.IsUnknown) { $item.Name = 'unknown' }
            $item.Tag = $key
            $item.BackColor = switch ($rowCache['_status']) { 'Green' { $colorGreen }; 'Yellow' { $colorYellow }; 'Red' { $colorRed }; default { $lv.BackColor } }
            $newItems.Add($item)
        }
        $lv.Items.AddRange($newItems.ToArray())
        $lv.Sort()
        $lv.EndUpdate()
        & $updateStatusLabel
    }

    [void]$lstEditions.Items.Add((T 'gui.songbrowser_all_editions'))
    foreach ($ed in $status.Editions) { [void]$lstEditions.Items.Add((Format-EditionDisplay $ed)) }
    # The change handler below isn't wired up yet at this point, so setting
    # the initial index can't fire it prematurely (unlike the main window's
    # radio buttons, which do need an explicit $script:Ready-style guard).
    $lstEditions.SelectedIndex = 0
    $lstEditions.Add_SelectedIndexChanged({
        param($s, $e)
        $script:TvFilterEdition = if ($lstEditions.SelectedIndex -le 0) { $null } else { $status.Editions[$lstEditions.SelectedIndex - 1] }
        & $refreshList
    })

    $searchDebounceTimer = New-Object System.Windows.Forms.Timer
    $searchDebounceTimer.Interval = 250
    $searchDebounceTimer.Add_Tick({ param($s, $e) $searchDebounceTimer.Stop(); & $refreshList })
    $txtSearch.Add_TextChanged({ param($s, $e) $searchDebounceTimer.Stop(); $searchDebounceTimer.Start() })

    $sorter = New-Object LegacyDownloader.SongListSorter
    $defaultSortCol = [Array]::IndexOf($script:TvVisibleFieldKeys, 'Title')
    if ($defaultSortCol -lt 0) { $defaultSortCol = 0 }
    $script:TvSort.Column = $defaultSortCol
    $sorter.Column = $defaultSortCol
    $lv.ListViewItemSorter = $sorter

    $updateSortArrows = {
        for ($i = 0; $i -lt $lv.Columns.Count; $i++) {
            $direction = if ($i -ne $script:TvSort.Column) { 0 } elseif ($script:TvSort.Ascending) { 1 } else { -1 }
            [LegacyDownloader.Native]::SetSortArrow($lv.Handle, $i, $direction)
        }
    }
    $lv.Add_ColumnClick({
        param($s, $e)
        if ($script:TvSort.Column -eq $e.Column) { $script:TvSort.Ascending = -not $script:TvSort.Ascending }
        else { $script:TvSort.Column = $e.Column; $script:TvSort.Ascending = $true }
        $sorter.Column = $script:TvSort.Column
        $sorter.Ascending = $script:TvSort.Ascending
        & $updateSortArrows
        $lv.Sort()
    })

    & $refreshList
    [void]$lv.Handle
    & $updateSortArrows

    $f.Controls.AddRange(@($txtSearch, $btnClearSearch, $btnDifficulty, $btnEffort, $lblEditions, $lstEditions, $btnColumns, $lv, $lblEmpty, $lblStatus, $btnClose))
    $f.Controls.AddRange($legendControls.ToArray())
    $btnClearSearch.BringToFront()

    # EM_SETCUEBANNER - same placeholder-text workaround the song picker's
    # own search box uses (LegacyDownloader.Native is already loaded by
    # then; this dialog is only ever reachable after the main window, which
    # loads it, has been built).
    [void]$txtSearch.Handle
    [void][LegacyDownloader.Native]::SendMessage($txtSearch.Handle, 0x1501, [IntPtr]::Zero, (T 'gui.trackedview_search_hint'))

    if ($env:LEGACY_GUI_SELFTEST) {
        $f.Show()
        [System.Windows.Forms.Application]::DoEvents()
        Write-Host "  TrackedView: $($status.Rows.Count) row(s), $($status.Editions.Count) edition(s), rendered $($lv.Items.Count)"
        try {
            & $applyDifficultyFilterToggle 0 $true
            [System.Windows.Forms.Application]::DoEvents()
            Write-Host "  Difficulty filter (unrated) narrowed to $($lv.Items.Count) row(s) with no exception"
            & $applyDifficultyFilterToggle 0 $false
            [System.Windows.Forms.Application]::DoEvents()
            if (-not (& $toggleColumnVisibility 'Artist' $false)) { throw "toggleColumnVisibility refused a legal hide" }
            [System.Windows.Forms.Application]::DoEvents()
            Write-Host "  Columns... hide Artist -> $($lv.Columns.Count) columns, no exception"
            [void](& $toggleColumnVisibility 'Artist' $true)
            [System.Windows.Forms.Application]::DoEvents()
        } catch {
            Write-Host "  SELFTEST FAILURE: $($_.Exception.Message)" -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 200
        $f.Dispose()
        return
    }
    [void]$f.ShowDialog()
    $f.Dispose()
}

# ===========================================================================
# software requirements: Kinect SDKs / VC++ redistributables / DirectX
# runtime. Two callers: the one-time check right after a brand-new install's
# first-run setup finishes (-FirstRun - "Continue" as the closing action),
# and the on-demand "Requirements" button on the main window (no -FirstRun -
# "Close"). Always re-detects live, never trusts a stale snapshot - see
# $refresh below, called both on open and after every install attempt.
# ===========================================================================

function New-StatusIcon([bool]$Ok) {
    # 16x16 status dot, drawn procedurally rather than shipping another
    # embedded-bitmap asset (like the language flags) - green+check for
    # installed, red+X for missing. Cached per-state so the grid's
    # per-cell Image assignment isn't allocating a fresh bitmap per row
    # per refresh.
    if ($null -eq $script:ReqStatusIcons) { $script:ReqStatusIcons = @{} }
    if ($script:ReqStatusIcons.ContainsKey($Ok)) { return $script:ReqStatusIcons[$Ok] }
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $color = if ($Ok) { [System.Drawing.Color]::FromArgb(46, 160, 90) } else { [System.Drawing.Color]::FromArgb(214, 69, 69) }
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($brush, 0, 0, 15, 15)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    if ($Ok) {
        $g.DrawLines($pen, @(
            (New-Object System.Drawing.Point(4, 8)), (New-Object System.Drawing.Point(7, 11)), (New-Object System.Drawing.Point(12, 5))))
    } else {
        $g.DrawLine($pen, 5, 5, 11, 11)
        $g.DrawLine($pen, 11, 5, 5, 11)
    }
    $pen.Dispose(); $brush.Dispose(); $g.Dispose()
    $script:ReqStatusIcons[$Ok] = $bmp
    return $bmp
}

function Show-RequirementsDialog {
    param([switch]$FirstRun)
    $gp = $script:Cfg.GamePath
    $script:ReqDialogItems = @()   # parallel to $grid's rows, refreshed below - script-scoped so Add_Click closures see updates a plain local wouldn't

    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'gui.requirements_title'
    $f.Font = $script:FontBase
    $f.BackColor = $script:ColorBg
    $f.ForeColor = $script:ColorText
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $f.MinimizeBox = $false; $f.MaximizeBox = $false

    # Before the download-progress feature, a click's whole download+install
    # sequence ran as one blocking call that never pumped Windows messages,
    # so the title-bar Close (X) was unreachable until it finished. The
    # progress callback below now calls DoEvents() on every tick, which DOES
    # process a queued close - closing mid-download would tear the form down
    # while Get-RequirementInstaller's read loop is still running against
    # its controls. Block that instead of trying to make every downstream
    # line defensive against a disposed control.
    $downloading = $false
    $f.Add_FormClosing({
        param($s, $e)
        if ($downloading) { $e.Cancel = $true }
    })

    $introText = if ($FirstRun) { T 'gui.requirements_intro_firstrun' } else { T 'gui.requirements_intro' }
    $introSize = [System.Windows.Forms.TextRenderer]::MeasureText(
        $introText, $script:FontBase, (New-Object System.Drawing.Size(452, 0)),
        [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $lblIntro = New-Label $introText 14 14 452 ($introSize.Height + 6)
    $lblIntro.ForeColor = $script:ColorMuted

    # Single grid - status icon + name + an inline per-row Install button -
    # replacing the earlier design's three stacked text boxes (a text
    # summary, a separate checkbox list, and a log) with one place that
    # shows everything. Same DataGridView conventions the editions
    # checklist elsewhere in this dialog set already established
    # (CellBorderStyle for a clean look, EditProgrammatically so clicks are
    # handled explicitly rather than through WinForms' own edit-in-place
    # behavior).
    # Grid height is sized exactly to its row count (no header row, since
    # ColumnHeadersVisible is off below) - a fixed guess left visible dead
    # space under the last row when the list is short.
    $itemCount = @(Get-RequirementDefinitions).Count
    $rowHeight = 32
    # +2 for the FixedSingle border, + (itemCount-1) for the SingleHorizontal
    # separator line drawn between every pair of rows.
    $gridHeight = $itemCount * $rowHeight + ($itemCount - 1) + 2

    $y = $lblIntro.Bottom + 10
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.SetBounds(14, $y, 452, $gridHeight)
    $grid.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $grid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $grid.ColumnHeadersVisible = $false
    $grid.RowHeadersVisible = $false
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.AllowUserToResizeColumns = $false
    $grid.MultiSelect = $false
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditProgrammatically
    $grid.StandardTab = $false
    $grid.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $grid.RowTemplate.Height = $rowHeight
    $grid.BackgroundColor = $script:ColorCard
    $grid.GridColor = $script:ColorBorder
    $grid.DefaultCellStyle.BackColor = $script:ColorCard
    $grid.DefaultCellStyle.ForeColor = $script:ColorText
    $grid.DefaultCellStyle.SelectionBackColor = $script:ColorCard
    $grid.DefaultCellStyle.SelectionForeColor = $script:ColorText
    $grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)

    $colIcon = New-Object System.Windows.Forms.DataGridViewImageColumn
    $colIcon.Width = 34
    $colIcon.ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
    $colIcon.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
    $colIcon.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    [void]$grid.Columns.Add($colIcon)

    # The name is a real link to that item's official Microsoft download
    # page (even for bundled items, which still have one for reference) -
    # styled + wired below, same "open externally, fall back to a
    # copy-this-link message" pattern the tutorial link elsewhere in this
    # file already uses.
    $linkFont = New-Object System.Drawing.Font($script:FontBase, [System.Drawing.FontStyle]::Underline)
    $colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colName.ReadOnly = $true
    $colName.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $colName.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    $colName.DefaultCellStyle.ForeColor = $script:ColorPrimary
    $colName.DefaultCellStyle.SelectionForeColor = $script:ColorPrimary
    $colName.DefaultCellStyle.Font = $linkFont
    [void]$grid.Columns.Add($colName)

    $colAction = New-Object System.Windows.Forms.DataGridViewButtonColumn
    $colAction.Width = 80
    $colAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $colAction.UseColumnTextForButtonValue = $false
    $colAction.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
    $colAction.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    $colAction.DefaultCellStyle.BackColor = $script:ColorCard
    [void]$grid.Columns.Add($colAction)

    $y += $grid.Height + 10
    $lblStatus = New-Label '' 14 $y 452 18
    $lblStatus.ForeColor = $script:ColorMuted
    $y += $lblStatus.Height + 10

    # Reserved space for the same reason $lblStatus's row is always
    # reserved even when its text is blank - a bar that only appears while
    # a download is running, without resizing this modal dialog around it,
    # needs its row accounted for in the fixed layout up front. Same
    # Style/MarqueeAnimationSpeed convention as the main window's $script:Bar.
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.SetBounds(14, $y, 452, 18)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $progressBar.MarqueeAnimationSpeed = 30
    $progressBar.Visible = $false
    $y += $progressBar.Height + 10

    # Manual re-check, for when automatic detection has a false negative
    # (something installed outside this app that the registry/DLL checks
    # don't happen to catch) - left-aligned, opposite Close, matching the
    # secondary-action-on-the-left convention the preview dialog's own
    # "Show file list" button already uses in this file.
    $btnRefresh = New-Btn (T 'gui.requirements_btn_refresh') 14 $y 0 32 $false
    $btnRefresh.Width = [Math]::Max(90, [System.Windows.Forms.TextRenderer]::MeasureText($btnRefresh.Text, $btnRefresh.Font).Width + 28)

    $closeLabel = if ($FirstRun) { T 'gui.requirements_btn_continue' } else { T 'gui.btn_close' }
    $btnClose = New-Btn $closeLabel 0 $y 0 32 $true
    $btnClose.Width = [Math]::Max(90, [System.Windows.Forms.TextRenderer]::MeasureText($btnClose.Text, $btnClose.Font).Width + 28)
    $btnClose.Left = 466 - $btnClose.Width
    $y += 46

    $refresh = {
        $script:ReqDialogItems = @(Get-RequirementsStatus -GamePath $gp)
        $grid.Rows.Clear()
        foreach ($it in $script:ReqDialogItems) {
            $idx = $grid.Rows.Add()
            $row = $grid.Rows[$idx]
            $row.Cells[0].Value = New-StatusIcon $it.Installed
            $name = $it.Name
            if ((-not $it.Installed) -and $it.Interactive) { $name += (T 'gui.requirements_interactive_note') }
            $row.Cells[1].Value = $name
            $actionCell = $row.Cells[2]
            if ($it.Installed) {
                # Disabled-looking, not just an empty cell - ReadOnly stops
                # WinForms' own edit-on-click, and the click handler itself
                # also no-ops for an installed row regardless (belt and
                # suspenders, in case ReadOnly alone doesn't block
                # CellContentClick for a button column in some WinForms
                # version).
                $actionCell.Value = T 'gui.requirements_status_installed'
                $actionCell.ReadOnly = $true
                $actionCell.Style.ForeColor = $script:ColorMuted
                $actionCell.Style.SelectionForeColor = $script:ColorMuted
                $actionCell.Style.BackColor = $script:ColorBg
                $actionCell.Style.SelectionBackColor = $script:ColorBg
            } else {
                $actionCell.Value = T 'gui.requirements_btn_install'
            }
            $row.Tag = $it.Id
        }
        $missingCount = @($script:ReqDialogItems | Where-Object { -not $_.Installed }).Count
        $lblStatus.Text = if ($missingCount -eq 0) { T 'gui.requirements_all_done' } else { '' }
    }
    & $refresh

    # Manual row/border/separator pixel math (RowTemplate.Height * count +
    # border + separator allowance) kept leaving a several-pixel sliver of
    # dead space below the last row - WinForms' actual rendered row bounds
    # don't line up exactly with that arithmetic. Measuring the REAL
    # rendered bottom of the last row directly (after the grid has a
    # handle and real rows, which & $refresh just populated) and
    # snug-fitting to that is exact regardless of what's actually eating
    # the extra pixels.
    [void]$grid.Handle
    if ($grid.Rows.Count -gt 0) {
        $lastRowRect = $grid.GetRowDisplayRectangle($grid.Rows.Count - 1, $true)
        $neededHeight = $lastRowRect.Bottom + 2   # +2 for the FixedSingle border
        if ($neededHeight -ne $grid.Height) {
            $delta = $neededHeight - $grid.Height
            $grid.Height = $neededHeight
            $lblStatus.Top += $delta
            $btnClose.Top += $delta
            $y += $delta
        }
    }

    $grid.Add_CellClick({
        param($s, $e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 1) { return }
        $row = $grid.Rows[$e.RowIndex]
        $id = $row.Tag
        $item = $script:ReqDialogItems | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $item -or -not $item.OfficialUrl) { return }
        try {
            Start-Process $item.OfficialUrl | Out-Null
        } catch {
            Info-Box (T 'gui.tutorial_open_failed' @{ url = $item.OfficialUrl }) (T 'gui.err_title')
        }
    })
    $grid.Add_CellMouseEnter({
        param($s, $e)
        if ($e.RowIndex -ge 0 -and $e.ColumnIndex -eq 1) { $grid.Cursor = [System.Windows.Forms.Cursors]::Hand }
    })
    $grid.Add_CellMouseLeave({
        param($s, $e)
        if ($e.RowIndex -ge 0 -and $e.ColumnIndex -eq 1) { $grid.Cursor = [System.Windows.Forms.Cursors]::Default }
    })

    # Installs run synchronously (Start-Process -Wait, inside Install-
    # Requirement) rather than through the async job+timer pattern the main
    # window's downloads use - a deliberate simplification, not an
    # oversight: each install is its own explicit, one-at-a-time click, not
    # a long unattended background transfer, and a wait cursor + disabled
    # grid communicates "busy" clearly enough for something this
    # short-lived. DoEvents before each blocking call at least flushes the
    # status line and cursor change to the screen first.
    $grid.Add_CellContentClick({
        param($s, $e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 2) { return }
        $row = $grid.Rows[$e.RowIndex]
        $id = $row.Tag
        $item = $script:ReqDialogItems | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $item -or $item.Installed) { return }

        # $downloading gates $f's FormClosing handler above - the download
        # loop below calls DoEvents() on every progress tick (unlike the old
        # single blocking call), so the title-bar Close is reachable again
        # mid-transfer; try/finally guarantees the flag (and the UI busy
        # state) clears even if something in here throws unexpectedly.
        $downloading = $true
        try {
            $f.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            $grid.Enabled = $false; $btnClose.Enabled = $false; $btnRefresh.Enabled = $false

            $lblStatus.Text = T 'gui.requirements_downloading' @{ name = $item.Name }
            # A bundled copy resolves instantly inside Get-RequirementInstaller
            # with no bytes moved, and so does a missing FetchUrl (directx has
            # none - it's bundled-only) - only show the bar for an item that's
            # actually about to hit the network, matching Get-RequirementInstaller's
            # own "bundled, then FetchUrl" gate.
            $willDownload = (-not $item.BundledPath) -and $item.FetchUrl
            if ($willDownload) {
                $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
                $progressBar.Value = 0
                $progressBar.Visible = $true
            }
            [System.Windows.Forms.Application]::DoEvents()
            $destDir = Join-Path $env:TEMP 'LegacyDownloaderRequirements'
            # GetNewClosure() is required here, not optional - without it this
            # scriptblock loses $item/$lblStatus/$progressBar entirely once
            # invoked from Get-RequirementInstaller's own scope in the Core
            # module, since a plain {} scriptblock resolves free variables in
            # the CALLER's scope at invocation time, not the scope it was
            # written in.
            $progressCallback = {
                param($pct, $received, $total)
                if ($pct -ge 0) {
                    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                    $progressBar.Value = $pct
                    $lblStatus.Text = T 'gui.requirements_downloading_pct' @{ name = $item.Name; pct = $pct }
                } else {
                    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
                }
                [System.Windows.Forms.Application]::DoEvents()
            }.GetNewClosure()
            $fetch = Get-RequirementInstaller -Item $item -DestDir $destDir -ProgressCallback $progressCallback
            $progressBar.Visible = $false
            if (-not $fetch.Ok) {
                $lblStatus.Text = T 'gui.requirements_download_failed' @{ name = $item.Name; url = $fetch.OfficialUrl }
            } else {
                $lblStatus.Text = T 'gui.requirements_installing' @{ name = $item.Name }
                [System.Windows.Forms.Application]::DoEvents()
                $res = Install-Requirement -Item $item -Path $fetch.Path
                if ($fetch.Downloaded) {
                    # Only ever the temp-folder copy Get-RequirementInstaller
                    # just downloaded - $fetch.Path points straight at the
                    # game's own Support\ folder when it came from there
                    # instead, and that must never be touched.
                    Remove-Item -LiteralPath $fetch.Path -Force -ErrorAction SilentlyContinue
                }

                # Trust a fresh real re-check over the installer's own exit
                # code for the message shown - not every installer here
                # follows the same MSI 0/3010/1638 exit-code convention
                # (DXSETUP.exe in particular is a legacy cab installer, exact
                # convention unverified), so asking "is it actually installed
                # now" is more honest than trusting a guessed-at exit code.
                $nowInstalled = (@(Get-RequirementsStatus -GamePath $gp | Where-Object { $_.Id -eq $item.Id }))[0].Installed
                $lblStatus.Text = if ($nowInstalled -and $res.RebootRequired) {
                    T 'gui.requirements_install_done_reboot' @{ name = $item.Name }
                } elseif ($nowInstalled) {
                    T 'gui.requirements_install_done' @{ name = $item.Name }
                } elseif ($res.Cancelled) {
                    T 'gui.requirements_install_cancelled' @{ name = $item.Name }
                } else {
                    T 'gui.requirements_install_failed' @{ name = $item.Name; code = $res.ExitCode }
                }
            }
        } finally {
            $downloading = $false
            $f.Cursor = [System.Windows.Forms.Cursors]::Default
            $grid.Enabled = $true; $btnClose.Enabled = $true; $btnRefresh.Enabled = $true
            $progressBar.Visible = $false
        }
        $savedStatus = $lblStatus.Text
        & $refresh
        if ($lblStatus.Text -eq (T 'gui.requirements_all_done') -or [string]::IsNullOrEmpty($lblStatus.Text)) {
            # $refresh only sets an "all done" or blank status - keep the
            # just-finished line visible instead of blanking it immediately.
            $lblStatus.Text = $savedStatus
        }
    })
    $btnRefresh.Add_Click({
        param($s, $e)
        $lblStatus.Text = ''
        & $refresh
    })
    $btnClose.Add_Click({ param($s, $e) $f.Close() })

    $f.ClientSize = New-Object System.Drawing.Size(480, $y)
    $f.CancelButton = $btnClose
    $f.Controls.AddRange(@($lblIntro, $grid, $lblStatus, $progressBar, $btnRefresh, $btnClose))

    if ($env:LEGACY_GUI_SELFTEST) {
        $f.Show()
        [System.Windows.Forms.Application]::DoEvents()
        Write-Host "  grid row count: $($grid.Rows.Count) (expect 6)"
        if ($grid.Rows.Count -ne 6) { Write-Host "  SELFTEST FAILURE: expected 6 rows" -ForegroundColor Red }
        Write-Host "  name column styled as a link: ForeColor=$($grid.Columns[1].DefaultCellStyle.ForeColor), Font.Underline=$($grid.Columns[1].DefaultCellStyle.Font.Underline)"
        # Exercises the actual Refresh button click end-to-end (not just
        # dialog construction) - real regression coverage for the
        # reentrancy-guard fix (btnRefresh.Enabled) and for $refresh
        # itself continuing to repopulate the grid correctly.
        $btnRefresh.PerformClick()
        [System.Windows.Forms.Application]::DoEvents()
        Write-Host "  after Refresh click: grid row count: $($grid.Rows.Count) (expect 6), btnRefresh.Enabled: $($btnRefresh.Enabled) (expect True)"
        if ($grid.Rows.Count -ne 6 -or -not $btnRefresh.Enabled) { Write-Host "  SELFTEST FAILURE: Refresh click left the dialog in a bad state" -ForegroundColor Red }
        # Static geometry only, not a live download - this dev machine has
        # every requirement installed already (see project notes), so a
        # real CellContentClick on any row no-ops before ever reaching
        # Get-RequirementInstaller. The live install->download->re-detect
        # path stays a manual/real-user verification, same as before.
        Write-Host "`n=== ProgressBar geometry ==="
        Write-Host "  Visible=$($progressBar.Visible) (expect False, no download in progress)  Left=$($progressBar.Left) Width=$($progressBar.Width) (expect Left/Width to match grid: Left=$($grid.Left) Width=$($grid.Width))"
        if ($progressBar.Visible) { Write-Host "  SELFTEST FAILURE: progress bar visible with no download in progress" -ForegroundColor Red }
        if ($progressBar.Left -ne $grid.Left -or $progressBar.Width -ne $grid.Width) { Write-Host "  SELFTEST FAILURE: progress bar not aligned with the grid" -ForegroundColor Red }
        if ($progressBar.Top -le $lblStatus.Bottom) { Write-Host "  SELFTEST FAILURE: progress bar overlaps the status label" -ForegroundColor Red }
        if ($progressBar.Bottom -ge $btnRefresh.Top) { Write-Host "  SELFTEST FAILURE: progress bar overlaps the Refresh button" -ForegroundColor Red }
        Start-Sleep -Milliseconds 200
        $f.Dispose()
        return
    }
    [void]$f.ShowDialog($script:Form)
    $f.Dispose()
}

function Refresh-Tracking {
    if ($script:Cfg.Editions.ToUpper() -eq 'AUTO') {
        $script:RbEverything.Checked = $true
        $script:LblTracking.Text = T 'gui.tracking_auto'
        if ($null -ne $script:BtnViewTracked) { $script:BtnViewTracked.Visible = $false }
        $script:LblTracking.Width = 464
    } else {
        $script:RbSpecific.Checked = $true
        $list = @($script:Cfg.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($list.Count -eq 0) {
            $script:LblTracking.Text = T 'gui.tracking_none'
            if ($null -ne $script:BtnViewTracked) { $script:BtnViewTracked.Visible = $false }
            $script:LblTracking.Width = 464
        } else {
            $songFilterMap = Get-SongFilterMap $script:Cfg.SongFilters
            # Whole-edition song counts come from whatever catalog was last
            # cached on disk (no live fetch just to render this summary,
            # same tradeoff the picker's own cache-only lookups make) - an
            # edition the cache doesn't know about yet just doesn't add to
            # the total, same as it not appearing in the picker's rows.
            $cachedCatalog = @(Get-CachedSongCatalog)
            $catalogCountByEdition = @{}
            foreach ($rec in $cachedCatalog) {
                if (-not $catalogCountByEdition.ContainsKey($rec.Edition)) { $catalogCountByEdition[$rec.Edition] = 0 }
                $catalogCountByEdition[$rec.Edition]++
            }
            $totalSongCount = 0
            foreach ($ed in $list) {
                $totalSongCount += if ($songFilterMap.Contains($ed)) { $songFilterMap[$ed].Count } elseif ($catalogCountByEdition.ContainsKey($ed)) { $catalogCountByEdition[$ed] } else { 0 }
            }
            # One total-songs number up front - the full per-edition/
            # per-song breakdown, with download status, is one click away
            # via "View tracked".
            $script:LblTracking.Text = T 'gui.tracking_summary' @{ songs = "$totalSongCount"; editions = "$($list.Count)" }
            if ($null -ne $script:BtnViewTracked) {
                $script:BtnViewTracked.Visible = $true
                $script:LblTracking.Width = [Math]::Max(0, $script:BtnViewTracked.Left - $script:LblTracking.Left - 8)
            }
        }
    }
    # Only meaningful in Specific mode - Everything already means "every
    # edition, downloaded or not," so there's nothing to narrow down.
    $script:BtnSelect.Enabled = (-not $script:Busy) -and $script:RbSpecific.Checked
}

function Apply-I18n {
    $script:Form.Text         = (T 'gui.window_title') + ' ' + $Version
    $script:LblLang.Text      = T 'gui.lang_label'
    $script:GrpFolder.Text    = T 'gui.group_folder'
    $script:BtnChange.Text    = T 'gui.btn_change'
    $script:GrpSongs.Text     = T 'gui.group_songs'
    $script:RbEverything.Text = T 'gui.rb_everything'
    $script:RbSpecific.Text   = T 'gui.rb_specific'
    $script:BtnSelect.Text    = T 'gui.btn_select_maps_songs'
    $script:BtnCheck.Text     = T 'gui.btn_check'
    $script:BtnExit.Text      = T 'gui.btn_exit'
    $script:BtnRequirements.Text = T 'gui.btn_requirements'
    $script:BtnViewTracked.Text = T 'gui.btn_view_tracked'
    $btnViewTrackedWidth = [System.Windows.Forms.TextRenderer]::MeasureText($script:BtnViewTracked.Text, $script:BtnViewTracked.Font).Width + 24
    $script:BtnViewTracked.Width = $btnViewTrackedWidth
    $script:BtnViewTracked.Left = 480 - $btnViewTrackedWidth
    Refresh-FolderStatus
    Refresh-Tracking
    Refresh-RequirementsButton
}

function Refresh-RequirementsButton {
    if ($null -eq $script:BtnRequirements) { return }
    $status = Get-RequirementsStatus -GamePath $script:Cfg.GamePath
    $missing = @($status | Where-Object { -not $_.Installed })
    $bothKinectMissing = (@($status | Where-Object { $_.Id -in @('kinect18', 'kinect20') -and -not $_.Installed })).Count -eq 2
    # Both Kinect SDKs missing (or most items missing) is the failure mode
    # Ven has a direct real-world report of actually crashing the game, not
    # just a theoretical gap - that case gets red rather than yellow.
    $colors = if ($missing.Count -eq 0) {
        @{ Base = [System.Drawing.Color]::FromArgb(224, 247, 231); Hover = [System.Drawing.Color]::FromArgb(200, 235, 210); Down = [System.Drawing.Color]::FromArgb(180, 225, 195) }
    } elseif ($bothKinectMissing -or $missing.Count -ge 4) {
        @{ Base = [System.Drawing.Color]::FromArgb(253, 226, 226); Hover = [System.Drawing.Color]::FromArgb(245, 200, 200); Down = [System.Drawing.Color]::FromArgb(235, 180, 180) }
    } else {
        @{ Base = [System.Drawing.Color]::FromArgb(255, 247, 219); Hover = [System.Drawing.Color]::FromArgb(250, 235, 180); Down = [System.Drawing.Color]::FromArgb(245, 225, 150) }
    }
    $script:BtnRequirements.BackColor = $colors.Base
    $script:BtnRequirements.FlatAppearance.MouseOverBackColor = $colors.Hover
    $script:BtnRequirements.FlatAppearance.MouseDownBackColor = $colors.Down
}

function Set-Busy([bool]$On) {
    $script:Busy = $On
    $enabled = -not $On
    $script:BtnCheck.Enabled  = $enabled
    $script:BtnChange.Enabled = $enabled
    $script:RbEverything.Enabled = $enabled
    $script:RbSpecific.Enabled   = $enabled
    $script:CmbLang.Enabled   = $enabled
    $script:BtnSelect.Enabled = $enabled -and $script:RbSpecific.Checked
}

function On-PlanReady($Plan, $ErrMsg, [bool]$IgnoredWrongLevel) {
    Set-Busy $false
    $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:Bar.Value = 0

    if ($ErrMsg) { Warn-Box ([string]$ErrMsg) (T 'gui.err_title'); return }
    if ($null -eq $Plan) { Warn-Box (T 'gui.netfail_body') (T 'gui.netfail_title'); return }

    if ($Plan.WrongLevel -and -not $IgnoredWrongLevel) {
        $r = [System.Windows.Forms.MessageBox]::Show($script:Form,
            (T 'gui.wronglevel_body' @{ path = $script:Cfg.GamePath; better = $Plan.BetterPath }),
            (T 'gui.wronglevel_title'),
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
            Save-Config -GamePath $Plan.BetterPath -Editions $script:Cfg.Editions
            $script:Cfg = Load-Config
            Refresh-FolderStatus
            return
        }
        if ($r -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
        Begin-Scan $true    # "No" -> check anyway
        return
    }

    if (-not $Plan.Ok) { Warn-Box (T 'gui.netfail_body') (T 'gui.netfail_title'); return }

    if ($Plan.TotalFiles -eq 0) {
        Info-Box (T 'gui.uptodate_body' @{ editions = $Plan.LocalEditions; songs = $Plan.LocalSongs }) (T 'gui.uptodate_title')
        Append-Log (T 'preview.up_to_date')
        Ensure-FirstRunRequirementsChecked
        return
    }

    $pv = Show-PreviewDialog $Plan
    if (-not $pv.Proceed) { return }

    Append-Log ("Found {0} file(s) ({1}) to download." -f $Plan.TotalFiles, (Format-Bytes $Plan.TotalBytes))
    Append-Log '----'
    Start-Downloads (Build-DownloadQueue $Plan $pv.Keep)
}

function On-Check {
    if (-not $script:Ready -or $script:Busy) { return }
    if ([string]::IsNullOrWhiteSpace($script:Cfg.GamePath)) {
        Warn-Box (T 'gui.folder_unset_warn') (T 'gui.window_title'); return
    }
    if ($script:RbSpecific.Checked -and [string]::IsNullOrWhiteSpace($script:Cfg.Editions)) {
        Warn-Box (T 'gui.no_editions_body') (T 'gui.window_title'); return
    }
    $script:TxtLog.Clear()
    Begin-Scan $false
}

# First run via "Download it for me": no preview, no scan - just pull the base
# game straight away (rclone --size-only fetches whatever's missing). Song packs
# are a deliberate next step once it's done.
function Start-FirstRunBaseDownload {
    if ($script:Busy) { return }
    $gp = $script:Cfg.GamePath
    if ([string]::IsNullOrWhiteSpace($gp)) { return }
    $exArgs = @()
    foreach ($e in (Get-BaseSyncExcludes -GamePath $gp)) { $exArgs += @('--exclude', $e) }
    $job = @{
        Label  = (T 'gui.job_base')
        Source = ($script:Conn + 'LegacyPC - Game')
        Dest   = $gp
        Extra  = $exArgs
        Kind   = 'base'
        Keep   = @()
    }
    $script:TxtLog.Clear()
    Append-Log (T 'gui.firstrun_base')
    Append-Log '----'
    Start-Downloads @($job)
}

function On-ChangeFolder {
    if (-not $script:Ready -or $script:Busy) { return }
    $p = Pick-Folder (T 'menu.picker_change') $script:Cfg.GamePath
    if (-not $p) { return }
    if (-not (Test-GameFolder $p)) {
        if (-not (Ask-YesNo (T 'menu.exe_not_found_use_anyway') (T 'gui.window_title'))) { return }
    }
    Save-Config -GamePath $p -Editions $script:Cfg.Editions
    $script:Cfg = Load-Config
    Refresh-FolderStatus
}

function Invoke-SongRemovalCleanup([string[]]$OldEditionList, [string]$OldSongFilters, $Res) {
    # Whole editions dropped, or editions narrowed to fewer songs, may have
    # local files the player no longer wants - ask once per affected
    # edition, same spirit as the tool's older "unchecked an edition"
    # cleanup prompt.
    $newEditionList = @($Res.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $plan = Get-SongRemovalPlan -OldEditions $OldEditionList -OldSongFilters $OldSongFilters -NewEditions $newEditionList -NewSongFilters $Res.SongFilters -Catalog $Res.Catalog
    foreach ($item in $plan) {
        $localDir = Join-Path $script:Cfg.GamePath "maps\$($item.Edition)"
        if (-not (Test-Path -LiteralPath $localDir)) { continue }
        if ($item.WholeEditionRemoved) {
            if (Ask-YesNo (T 'maps.delete_or_keep' @{ edition = $item.Edition }) (T 'gui.window_title')) {
                try { Remove-Item -LiteralPath $localDir -Recurse -Force -ErrorAction Stop }
                catch { Warn-Box (T 'maps.cant_delete' @{ edition = $item.Edition }) (T 'gui.err_title') }
            }
        } else {
            if (Ask-YesNo (T 'maps.delete_songs_or_keep' @{ count = $item.RemovedCodes.Count; edition = $item.Edition }) (T 'gui.window_title')) {
                $failed = 0
                foreach ($code in $item.RemovedCodes) {
                    $target = Join-Path $localDir "${code}_pc.ipk"
                    if (Test-Path -LiteralPath $target) {
                        try { Remove-Item -LiteralPath $target -Force -ErrorAction Stop } catch { $failed++ }
                    }
                }
                if ($failed -gt 0) { Warn-Box (T 'maps.cant_delete_songs' @{ edition = $item.Edition }) (T 'gui.err_title') }
            }
        }
    }
}

function On-SongModeChanged {
    if (-not $script:Ready -or $script:Busy) { return }
    if ($script:RbEverything.Checked) {
        if ($script:Cfg.Editions.ToUpper() -ne 'AUTO') {
            Save-Config -GamePath $script:Cfg.GamePath -Editions 'AUTO'
            $script:Cfg = Load-Config
        }
        Refresh-Tracking
        return
    }
    # switched to "specific" - open the picker immediately rather than
    # leaving an empty selection hanging (same behavior the button gives).
    if ($script:Cfg.Editions.ToUpper() -eq 'AUTO') {
        $res = Show-SongBrowserDialog -SeedFromDisk
        if ($null -eq $res) {
            # cancelled -> fall back to Everything, nothing changed
            $script:RbEverything.Checked = $true
            return
        }
        Invoke-SongRemovalCleanup -OldEditionList @(Get-LocalEditions $script:Cfg.GamePath) -OldSongFilters '' -Res $res
        Save-Config -GamePath $script:Cfg.GamePath -Editions $res.Editions -SongFilters $res.SongFilters
        $script:Cfg = Load-Config
    }
    Refresh-Tracking
}

function On-SelectMapsSongs {
    if (-not $script:Ready -or $script:Busy) { return }
    $res = Show-SongBrowserDialog
    if ($null -eq $res) { return }
    $oldEditionList = @(if ($script:Cfg.Editions.ToUpper() -eq 'AUTO') { Get-LocalEditions $script:Cfg.GamePath } else { $script:Cfg.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } })
    Invoke-SongRemovalCleanup -OldEditionList $oldEditionList -OldSongFilters $script:Cfg.SongFilters -Res $res
    Save-Config -GamePath $script:Cfg.GamePath -Editions $res.Editions -SongFilters $res.SongFilters
    $script:Cfg = Load-Config
    $script:RbSpecific.Checked = $true
    Refresh-Tracking
}

function On-LangChanged {
    if (-not $script:Ready -or $script:Busy) { return }
    $i = $script:CmbLang.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:Langs.Count) { return }
    $code = $script:Langs[$i].Code
    if ($code -eq $script:Cfg.Lang) { return }
    $null = Initialize-Language -Code $code
    Save-Config -GamePath $script:Cfg.GamePath -Editions $script:Cfg.Editions -Lang $code
    $script:Cfg = Load-Config
    Apply-I18n
}

function Build-MainForm {
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Font = $script:FontBase
    $script:Form.BackColor = $script:ColorBg
    $script:Form.ForeColor = $script:ColorText
    $script:Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $script:Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $script:Form.ClientSize = New-Object System.Drawing.Size(520, 536)
    $script:Form.MaximizeBox = $false

    # Top bar: Language label & Owner-Draw ComboBox
    $script:LblLang = New-Label '' 260 14 70 24
    $script:LblLang.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $script:LblLang.ForeColor = $script:ColorMuted

    $script:CmbLang = New-Object System.Windows.Forms.ComboBox
    $script:CmbLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:CmbLang.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $script:CmbLang.ItemHeight = 22
    $script:CmbLang.Font = $script:FontBase
    $script:CmbLang.SetBounds(336, 12, 172, 26)
    $script:CmbLang.BackColor = $script:ColorCard
    $script:CmbLang.ForeColor = $script:ColorText

    # Owner-draw handler for Language ComboBox (Flag Icon + Native Name)
    $script:CmbLang.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0 -or $e.Index -ge $script:Langs.Count) { return }
        $e.DrawBackground()

        $lang = $script:Langs[$e.Index]
        $bmp = Get-FlagBitmap $lang.Code

        # Draw flag centered vertically
        $flagX = $e.Bounds.X + 6
        $flagY = $e.Bounds.Y + [Math]::Max(0, [int](($e.Bounds.Height - 15) / 2))
        if ($null -ne $bmp) {
            $e.Graphics.DrawImage($bmp, $flagX, $flagY, 20, 15)
            # Subtle 1px border around flag
            $borderPen = [System.Drawing.Pens]::LightGray
            $e.Graphics.DrawRectangle($borderPen, $flagX - 1, $flagY - 1, 21, 16)
        }

        # Text rendering
        $textX = $flagX + 28
        $textBounds = New-Object System.Drawing.RectangleF($textX, $e.Bounds.Y, ($e.Bounds.Width - $textX), $e.Bounds.Height)
        $brush = if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) {
            New-Object System.Drawing.SolidBrush([System.Drawing.SystemColors]::HighlightText)
        } else {
            New-Object System.Drawing.SolidBrush($script:ColorText)
        }
        $sf = New-Object System.Drawing.StringFormat
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $sf.Alignment = [System.Drawing.StringAlignment]::Near

        $e.Graphics.DrawString($lang.NativeName, $e.Font, $brush, $textBounds, $sf)
        $brush.Dispose()
        $sf.Dispose()
        $e.DrawFocusRectangle()
    })

    foreach ($l in $script:Langs) { [void]$script:CmbLang.Items.Add($l.NativeName) }
    for ($i = 0; $i -lt $script:Langs.Count; $i++) {
        if ($script:Langs[$i].Code -eq $script:Cfg.Lang) { $script:CmbLang.SelectedIndex = $i; break }
    }
    if ($script:CmbLang.SelectedIndex -lt 0 -and $script:CmbLang.Items.Count -gt 0) { $script:CmbLang.SelectedIndex = 0 }
    $script:CmbLang.Add_SelectedIndexChanged({ param($s, $e) On-LangChanged })

    # Game Folder GroupBox
    $script:GrpFolder = New-Object System.Windows.Forms.GroupBox
    $script:GrpFolder.Font = $script:FontBold
    $script:GrpFolder.ForeColor = [System.Drawing.Color]::FromArgb(30, 58, 110)
    $script:GrpFolder.SetBounds(12, 44, 496, 84)

    $script:TxtFolder = New-Object System.Windows.Forms.TextBox
    $script:TxtFolder.ReadOnly = $true
    $script:TxtFolder.Font = $script:FontBase
    $script:TxtFolder.BackColor = [System.Drawing.Color]::FromArgb(242, 245, 248)
    $script:TxtFolder.ForeColor = $script:ColorText
    $script:TxtFolder.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:TxtFolder.SetBounds(16, 24, 376, 23)

    $script:BtnChange = New-Btn '' 400 22 80 26 $false
    $script:BtnChange.Add_Click({ param($s, $e) On-ChangeFolder })

    $script:LblFolder = New-Label '' 16 52 464 20
    $script:GrpFolder.Controls.AddRange(@($script:TxtFolder, $script:BtnChange, $script:LblFolder))

    # Songs GroupBox
    $script:GrpSongs = New-Object System.Windows.Forms.GroupBox
    $script:GrpSongs.Font = $script:FontBold
    $script:GrpSongs.ForeColor = [System.Drawing.Color]::FromArgb(30, 58, 110)
    $script:GrpSongs.SetBounds(12, 134, 496, 116)

    $script:RbEverything = New-Object System.Windows.Forms.RadioButton
    $script:RbEverything.Font = $script:FontBase
    $script:RbEverything.ForeColor = $script:ColorText
    $script:RbEverything.SetBounds(16, 22, 464, 22)

    $script:RbSpecific = New-Object System.Windows.Forms.RadioButton
    $script:RbSpecific.Font = $script:FontBase
    $script:RbSpecific.ForeColor = $script:ColorText
    $script:RbSpecific.SetBounds(16, 46, 190, 22)

    $script:BtnSelect = New-Btn '' 210 44 272 26 $false
    $script:BtnSelect.Add_Click({ param($s, $e) On-SelectMapsSongs })

    $script:LblTracking = New-Label '' 16 82 340 18
    $script:LblTracking.ForeColor = $script:ColorMuted

    # Opens Show-TrackedViewDialog - only shown (and only ever relevant) for
    # a Specific selection with something actually tracked; Everything
    # mode's "Tracking: everything" summary is already as compact as it
    # gets (see Refresh-Tracking). Sits 10px below BtnSelect's bottom edge
    # (70) rather than flush against it. Resized to fit its own translated
    # text (recomputed in Apply-I18n) the same way the song browser's own
    # Difficulty/Effort filter buttons are - a fixed width doesn't fit
    # every language's translation of "View tracked".
    $script:BtnViewTracked = New-Btn '' 356 80 124 24 $false
    $script:BtnViewTracked.Add_Click({ param($s, $e) Show-TrackedViewDialog })

    $script:RbEverything.Add_CheckedChanged({ param($s, $e) if ($script:RbEverything.Checked) { On-SongModeChanged } })
    $script:RbSpecific.Add_CheckedChanged({ param($s, $e) if ($script:RbSpecific.Checked) { On-SongModeChanged } })
    $script:GrpSongs.Controls.AddRange(@($script:RbEverything, $script:RbSpecific, $script:BtnSelect, $script:LblTracking, $script:BtnViewTracked))

    # Check for updates button (Primary CTA)
    $script:BtnCheck = New-Btn '' 12 258 496 38 $true
    $script:BtnCheck.Add_Click({ param($s, $e) On-Check })

    # Progress bar & Status
    $script:Bar = New-Object System.Windows.Forms.ProgressBar
    $script:Bar.SetBounds(12, 304, 496, 18)
    $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:Bar.MarqueeAnimationSpeed = 30

    $script:LblProg = New-Label '' 12 326 496 18
    $script:LblProg.ForeColor = $script:ColorMuted

    # Activity Log
    $script:TxtLog = New-Object System.Windows.Forms.TextBox
    $script:TxtLog.Multiline = $true; $script:TxtLog.ReadOnly = $true
    $script:TxtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:TxtLog.SetBounds(12, 348, 496, 140)
    $script:TxtLog.Font = $script:FontMono
    $script:TxtLog.BackColor = $script:ColorCard
    $script:TxtLog.ForeColor = $script:ColorText
    $script:TxtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    # Requirements status button - fixed size, left of Exit (same size, per
    # Ven's layout call). Color reflects aggregate status - green/yellow/red,
    # same convention as the tracked-songs dialog's row coloring - refreshed
    # in Refresh-RequirementsButton (called from Apply-I18n and after the
    # dialog closes, since an install may have just changed the status).
    $script:BtnRequirements = New-Btn '' 318 496 90 28 $false
    $script:BtnRequirements.Add_Click({ param($s, $e) Show-RequirementsDialog; Refresh-RequirementsButton })

    # Exit Button
    $script:BtnExit = New-Btn '' 418 496 90 28 $false
    $script:BtnExit.Add_Click({ param($s, $e) $script:Form.Close() })

    $script:Form.Controls.AddRange(@(
            $script:LblLang, $script:CmbLang,
            $script:GrpFolder, $script:GrpSongs,
            $script:BtnCheck, $script:Bar, $script:LblProg, $script:TxtLog, $script:BtnRequirements, $script:BtnExit
        ))

    $script:ScanTimer = New-Object System.Windows.Forms.Timer
    $script:ScanTimer.Interval = 250
    $script:ScanTimer.Add_Tick({ param($s, $e) Poll-Scan })

    $script:DlTimer = New-Object System.Windows.Forms.Timer
    $script:DlTimer.Interval = 500
    $script:DlTimer.Add_Tick({ param($s, $e) Poll-Download })

    $script:Form.Add_FormClosing({
            param($s, $e)
            if ($script:Busy -and $script:Job) {
                if (-not (Ask-YesNo (T 'gui.cancel_download_q') (T 'gui.btn_stop'))) { $e.Cancel = $true; return }
                try { $script:Job.Process.Kill() } catch { }
                try { Complete-RcloneCopy -Job $script:Job | Out-Null } catch { }
            }
            try { $script:DlTimer.Stop() } catch { }
            try { $script:ScanTimer.Stop() } catch { }
            if ($script:ScanJob) {
                try { Stop-Job $script:ScanJob -ErrorAction SilentlyContinue } catch { }
                try { Remove-Job $script:ScanJob -Force -ErrorAction SilentlyContinue } catch { }
            }

            # Cleanup GDI bitmap resources
            foreach ($bmp in $script:FlagBitmaps.Values) {
                try { if ($null -ne $bmp) { $bmp.Dispose() } } catch { }
            }
            $script:FlagBitmaps.Clear()
        })

    # First run via "Download it for me" - the moment the window is up, start
    # pulling the base game with no preview. Songs are a deliberate second step.
    # "I already have it" just lands here with no auto-action. If the chosen
    # folder already has Legacy.exe, fall back to a normal checked update so a
    # patched/modded copy isn't overwritten blindly.
    $script:Form.Add_Shown({
            param($s, $e)
            if ($script:AutoRunDone) { return }
            $script:AutoRunDone = $true
            if ($script:FirstRunMode -eq 'get' -and -not [string]::IsNullOrWhiteSpace($script:Cfg.GamePath)) {
                if (Test-GameFolder $script:Cfg.GamePath) { On-Check } else { Start-FirstRunBaseDownload }
            }
        })

    Apply-I18n
    $script:Ready = $true
}

# ===========================================================================
# run
# ===========================================================================

if (-not $env:LEGACY_GUI_SELFTEST -and [string]::IsNullOrWhiteSpace($script:Cfg.GamePath)) {
    $script:FirstRunMode = Run-SetupDialog
    # 'have': nothing async follows (no base download to wait on, unlike
    # 'get' - see Ensure-FirstRunRequirementsChecked for that path), so the
    # one-time check can just run right here, before the main window exists.
    # $script:Form is still $null at this point - same as Run-SetupDialog's
    # own ShowDialog() call just above, which has the same constraint.
    if ($script:FirstRunMode -eq 'have') {
        Show-RequirementsDialog -FirstRun
        $script:ReqsFirstRunChecked = $true
    }
}

Build-MainForm

if ($env:LEGACY_GUI_SELFTEST) {
    function Dump-Ctl($c, $d) {
        $pad = ' ' * $d
        Write-Host ("{0}{1}  text='{2}'  @({3},{4}) {5}x{6}" -f $pad, $c.GetType().Name, $c.Text, $c.Left, $c.Top, $c.Width, $c.Height)
        foreach ($k in $c.Controls) { Dump-Ctl $k ($d + 2) }
    }
    Write-Host "=== main form control tree ==="
    Dump-Ctl $script:Form 0
    Write-Host "`n=== i18n sanity (a few keys) ==="
    foreach ($k in @('gui.btn_check', 'gui.rb_everything', 'gui.folder_ok', 'gui.progress_downloading')) {
        Write-Host ("  {0} => {1}" -f $k, (T $k @{ songs = 1; label = 'x'; pct = 1; speed = '1 KB'; eta = '1s' }))
    }
    Write-Host "`n=== Select maps/songs button gating ==="
    Write-Host "  Everything selected: RbEverything.Checked=$($script:RbEverything.Checked)  BtnSelect.Enabled=$($script:BtnSelect.Enabled) (expect False)"
    Write-Host "`n=== Show-TrackedViewDialog (no network, cached catalog only) ==="
    try {
        Show-TrackedViewDialog
        Write-Host "  ran with no exception"
    } catch {
        Write-Host "  SELFTEST FAILURE: Show-TrackedViewDialog threw: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n=== Show-RequirementsDialog (real Get-RequirementsStatus against this machine - structural test only, not asserting specific installed/missing values, same spirit as the tracked-view test above) ==="
    try {
        Show-RequirementsDialog
        Show-RequirementsDialog -FirstRun
        Write-Host "  ran with no exception (both -FirstRun and non)"
    } catch {
        Write-Host "  SELFTEST FAILURE: Show-RequirementsDialog threw: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "`n=== BtnRequirements gating ==="
    Write-Host "  Left=$($script:BtnRequirements.Left) Width=$($script:BtnRequirements.Width) (expect same width as BtnExit=$($script:BtnExit.Width), positioned to its left)"
    if ($script:BtnRequirements.Width -ne $script:BtnExit.Width) { Write-Host "  SELFTEST FAILURE: width mismatch" -ForegroundColor Red }
    if ($script:BtnRequirements.Right + 10 -ne $script:BtnExit.Left) { Write-Host "  SELFTEST FAILURE: not positioned 10px left of BtnExit" -ForegroundColor Red }
    Write-Host "`n=== BtnViewTracked / LblTracking geometry ==="
    Write-Host "  LblTracking: Right=$($script:LblTracking.Right)  BtnViewTracked: Left=$($script:BtnViewTracked.Left)"
    if ($script:RbSpecific.Checked -and ($script:LblTracking.Right -gt $script:BtnViewTracked.Left)) {
        Write-Host "  SELFTEST FAILURE: LblTracking overlaps BtnViewTracked" -ForegroundColor Red
    }
    Write-Host "`n=== Show-SongBrowserDialog (waits for the real async catalog load) ==="
    $null = Show-SongBrowserDialog
    $script:Form.Dispose()
    Write-Host "`nSELFTEST OK"
    return
}

[System.Windows.Forms.Application]::Run($script:Form)
