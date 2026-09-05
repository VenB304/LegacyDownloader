# LegacyDownloader.Gui.ps1 - the windowed interface (default front-end).
#
# Dot-sourced by LegacyDownloader.ps1 after the core module is imported,
# Initialize-LegacyCore has run and Initialize-Language has set the language.
# Relies on $Core being set by the entry script. The console front-end
# (LegacyDownloader.Console.ps1 / the -Console switch) is the fallback.

$ErrorActionPreference = 'Stop'

if (-not $Core) {
    [System.Windows.Forms.MessageBox]::Show("Please run LegacyDownloader.bat, not this file directly.") | Out-Null
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
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
$script:Queue     = @()                   # remaining {Label;Source;Dest;Extra}
$script:LastObject = ''
$script:FirstRunMode  = $null             # 'get' / 'have' when the setup dialog just ran
$script:AutoRunDone   = $false            # one-shot guard for the first-run auto action

# ---- embedded flag bitmaps (20x15 PNGs) ----
$script:FlagB64 = @{
    'de'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAABxUlEQVQ4ja3Ty24URxQA0FPVNWT8APwIEYoMgjVIZpdIUf4i4g/5APb5CUvsYY1lGxuPPY/uWyyqEZOJ2SBaurpd1apT91Z3p1LK3xFxjOf4LSK2kXLOq4j4jEucjXGOT5hhjowdPBrXH6eU0r94VWs9QHL3tRyxszVwMYLbI/gMuwn1O8gPXflnYlAyjvAUB7g3Pqi4xpXW48WY53cg09F4jPIP/tAOYH8E6xgz7Y2sg5e4wbCG7eN3rd30lvoS3Vpl63lzbjmC/TieYgsrvEPZWqvoLmAzT/BgY83X+0BZh9Iu6ZdWbl0wzFu+C94EQyu1dEdsv2B6RN5rYOqIBXFLXDFcMlzQXzFcEzNqbVCa0O2z9Zj725Td1+z9xfQJqfx/61gQnxo4XH4DRUPThLKPR+yeUqZ/MnnaqvpPL2PkCflXyuF3+hznlivqR0odB/MFfU8M1Gj/YE50uX2sXyNtHmIlgtt5W1dqcHruuu996AenQ++mMqimXbKTk73MYc4OuuReyW2jrLU8DCyX6uzW+RBOSq3enF04ifB+lZx2K7NIovamkezUsJc4iMEhDifFw8z9LplEqKvezWLp49B7X6uTL16L4e3tydldAAAAAElFTkSuQmCC'
    'en'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAMAAADTRh9nAAABgFBMVEUBG1SYl6efDSfKfooAG1cCLGy+n6UCIF0AE0YAGlSpL0LAlZynUmifDSeSkqLTiJjZ2dm7u7u2b3i/VG6vt8NGZJGUPUjFpq1AS2xRT3VeWoAAEkV5cImapbm6FDSjCh+mCSCflKR9hJa3EzMCKWmGeZLHDizJEjLCDCfkj5/afo7OIUEAF1TgeotTZpWpscjFvMwCK3DGGzXLFjjRPlbll6PliJrqp7Lonq2tuM9dcJkBIWTPL0rVW3HduMOjVHNhVH8qT4mwW3EWKmK7CyNGWYMxRXbLJkDt1Nvcc4P39/q8hZ/ck6DsydHIbYSGU3mWFSerqr6YhKWifJZ8T3Q7ToWZXmxfe6jBa4rayNTptb3Iz98VOXemnK5NUHW4tsuPmbHbipe5sMStpLfhhJO9fZFpWIbpqrWsGDdTW3a1bH+Ch6uPepXda33NT2GEg6bByNqvKkT77/IAET+HXoj67O7rusUoNFhtNkqMocKgbIHNw9IpR4Pcz9rV2eSdlqS0UDBzAAAAJnRSTlM1jXrzwaw9ta1CdaTTZ1XsbGzsvI2jvf6jvr6cVNT55/nUjeecVBCdCscAAAEnSURBVBjTHdADlsMAFADAX7trW1HjpE3T1LZtrG3j6vte5wgD+tnFJZ1Od6hS2+wmADAdmS2wMOOXG12Om2wfbGkNBsO6VfMHhabL3foIcWMBZRSlGwyP2DiE6Oem61WmBygqc7VC3snSJHChRsntfuz8oOj9aYA4G9DxPnjKmQxO4ZKEokk/nkwzd5U6XPpEr8OR8IoIkqKOnSMidVuEc0EQHA4BmUJ5HsOiRXjwUQTudFE3CCJ6EzyfEH11+Cxfyekc7s9hWFvCqexJ5foCYt8eViICQRbDfjsv7myPjjyB4vnC89WaMsYwJsa0iXC1/wYxdhQIRkhyEo0yZHzYchLhd+hprGsGo1a7t7M7JMmIp7QyvwwW8+Y0x25T728YjcZV1Zz+HwHdQPKkb2RfAAAAAElFTkSuQmCC'
    'es'      = 'iVBORw0KGgoAAAANSUhEUgAAABQAAAAPCAYAAADkmO9VAAACmUlEQVQ4y22Ty25jRRCGv2r3sR1fZpJ4MmRAkBkWLBAoiH0WiCUPxcMgJN6DBRuEyEgsAI2GEZpLHHzie+zTp+tnYTsJEd0qVau79P1VrSr77pNPzzz7qbs/C+6PDXXkWMZTFrMsn7j7SNjIlUtzjTMs3FkJBVDXPR9JeubSafQ6f7tn9kXD7JAQzAQKjivgiIyRQ6PK7qUsjLL5OEuLbL6WCCZ1DDvCeDpx70W5f91tRKIZutmG2Cwn4PJmNjvO0nHGcNvcSwKEGSDjChEpMvtPE52jiqJXY9HBRK4gr4y0CKS5sZ4GqpmRFlBfbwQFEKH50GkOalJvTXzyVcnJaaL3OFH0akIUo2GH+TDQfSC6rTVpHqimgWoWqJdGWhpyIUGIovkg0zzIFKkmvnc2ZnACMWwkyzIwfFXw+/MOH36W+PzLJf33EwDapaXbs219SvDqDwjYNsg3/u27J5QvjOnkI8r1Ga//eYT0X9gOtIPhoK0F+Z1Ah+XVCYtJg8niAPnHXPx5jHwreC92Z7t3zxDuK68iNA8S9fgN899+RGqh/wPpNqu7WcYb9bApa//4HU1bY3tj+ipJH5xg3Mvu7hfcgecEsZoGLp8XVJcNVtPAejHFVdDKNa0Clr+OeD1s0eo7Rdcp2qJo6waYK1hNjPJt4MUvhv3wTV+Pxi3WF4HVLOC1cLYt0XbinhO7ugHGthPbm7YXoq7gemJcXQR+/lvENz+18dDA3Uk4rlugLYUtDRsZgYCJ7SSBpE21ElniWiJ5JrrE2PM8u/+V4bJGS3dlzNpIXWAfMTB0aNC07UiyBWaJWtI1Kl2cR5e+n3k+z9hLzC9dWtQ1TqPRdvduNvYNDrMxcPdBhIeG9SUVQkrSMsEwu7800/m/wsXxL/gOJaYAAAAASUVORK5CYII='
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
    } else {
        $b.Font = $script:FontBase
        $b.BackColor = $script:ColorCard
        $b.ForeColor = $script:ColorText
        $b.FlatAppearance.BorderColor = $script:ColorBorder
        $b.FlatAppearance.BorderSize = 1
    }
    return $b
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
        param($mod, $dir, $lang, $gp, $eds, $ignore, $outFile)
        Import-Module $mod -DisableNameChecking
        $null = Initialize-LegacyCore -ScriptDir $dir
        $null = Initialize-Language -Code $lang
        $plan = if ($ignore) {
            Get-UpdatePlan -GamePath $gp -Editions $eds -IgnoreWrongLevel
        } else {
            Get-UpdatePlan -GamePath $gp -Editions $eds
        }
        $plan | Export-Clixml -Path $outFile
    } -ArgumentList $script:ModPath, $script:AppDir, (Get-LanguageCode), $script:Cfg.GamePath, $script:Cfg.Editions, $IgnoreWrong, $script:ScanOut

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
        try { if (Test-Path $script:ScanOut) { $plan = Import-Clixml -Path $script:ScanOut } } catch { $errMsg = $_.Exception.Message }
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
        } else {
            Append-Log ("$([char]0x2717) " + (T 'gui.progress_failed_line' @{ label = $script:Job.Label; code = $code }))
            $script:Job = $null
            $script:DlTimer.Stop()
            Set-Busy $false
            Warn-Box (T 'gui.failed_body' @{ code = $code }) (T 'gui.failed_title')
            return
        }
        $script:Job = $null
    }
    if ($script:Queue.Count -eq 0) { Finish-Downloads; return }
    $spec = $script:Queue[0]; $script:Queue.RemoveAt(0)
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
}

function Build-DownloadQueue($Plan, $KeepFiles) {
    $gp = $script:Cfg.GamePath
    $jobs = @()

    $baseNeedsSync = (@($Plan.BaseNormal).Count -gt 0) -or (@($Plan.BaseAsk | Where-Object { $KeepFiles -notcontains $_ }).Count -gt 0)
    if ($baseNeedsSync -or $Plan.MapsMissing) {
        $ex = Get-BaseSyncExcludes -GamePath $gp -KeepFiles $KeepFiles
        $exArgs = @()
        foreach ($e in $ex) { $exArgs += @('--exclude', $e) }
        $jobs += @{ Label = (T 'gui.job_base'); Source = ($script:Conn + 'LegacyPC - Game'); Dest = $gp; Extra = $exArgs }
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
            $jobs += @{ Label = $dispLabel; Source = ($script:Conn + "maps/$ed"); Dest = (Join-Path $gp "maps\$ed"); Extra = @() }
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
        foreach ($x in $ba) { [void]$clb.Items.Add($x, $false) }   # unchecked = keep yours
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
# editions dialog
# ===========================================================================

function Show-EditionsDialog {
    # returns 'AUTO' is never returned here; returns a csv, '' (nothing picked), or $null (cancel)
    $old = $script:Form.Cursor
    $script:Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $rawRemote = @()
    try { $rawRemote = @(Get-RemoteEditions) } catch { $rawRemote = @() }
    $script:Form.Cursor = $old
    if (-not $rawRemote -or $rawRemote.Count -eq 0) {
        Warn-Box (T 'gui.netfail_body') (T 'gui.netfail_title')
        return $null
    }
    $script:CachedRemoteEditions = $rawRemote
    $remote = $rawRemote

    $pre = @()
    if ($script:Cfg.Editions.ToUpper() -eq 'AUTO') {
        $pre = @(Get-LocalEditions $script:Cfg.GamePath)
    } else {
        $pre = @($script:Cfg.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = T 'gui.editions_title'
    $f.Font = $script:FontBase
    $f.BackColor = $script:ColorBg
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $f.ClientSize = New-Object System.Drawing.Size(460, 460)
    $f.MinimizeBox = $false; $f.MaximizeBox = $false

    $hint = New-Label (T 'gui.editions_hint') 14 12 432 20
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.CheckOnClick = $true
    $clb.Font = $script:FontBase
    $clb.BackColor = $script:ColorCard
    $clb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $clb.SetBounds(14, 36, 432, 310)

    $itemCodes = @()
    foreach ($e in $remote) {
        $disp = Format-EditionDisplay $e
        $itemCodes += $e
        $i = $clb.Items.Add($disp)
        if ($pre -contains $e) { $clb.SetItemChecked($i, $true) }
    }

    $bAll    = New-Btn (T 'gui.btn_all') 14 360 90 28 $false
    $bNone   = New-Btn (T 'gui.btn_none') 110 360 90 28 $false
    $bOk     = New-Btn (T 'gui.btn_ok') 14 402 208 34 $true
    $bCancel = New-Btn (T 'gui.btn_cancel') 238 402 208 34 $false

    $bAll.Add_Click({ param($s, $e) for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $true) } })
    $bNone.Add_Click({ param($s, $e) for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $false) } })
    $bOk.Add_Click({
        param($s, $e)
        $cnt = 0
        for ($i = 0; $i -lt $clb.Items.Count; $i++) { if ($clb.GetItemChecked($i)) { $cnt++ } }
        if ($cnt -eq 0) {
            Warn-Box (T 'gui.no_editions_body') (T 'gui.err_title')
            return
        }
        $f.Tag = 'ok'; $f.Close()
    })
    $bCancel.Add_Click({ param($s, $e) $f.Tag = ''; $f.Close() })
    $f.AcceptButton = $bOk
    $f.CancelButton = $bCancel

    $f.Controls.AddRange(@($hint, $clb, $bAll, $bNone, $bOk, $bCancel))
    $f.ShowDialog($script:Form) | Out-Null

    $ret = $null
    if ($f.Tag -eq 'ok') {
        $sel = @()
        for ($i = 0; $i -lt $clb.Items.Count; $i++) {
            if ($clb.GetItemChecked($i)) {
                $sel += $itemCodes[$i]
            }
        }
        if ($sel.Count -eq 0) {
            $ret = ''
        } elseif ($sel.Count -eq $remote.Count) {
            $ret = 'AUTO'
        } else {
            $ret = (@($sel | Sort-EditionNames) -join ',')
        }
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
        try { New-Item -ItemType Directory -Force -Path $path -ErrorAction Stop | Out-Null } catch {
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

function Refresh-Tracking {
    if ($script:Cfg.Editions.ToUpper() -eq 'AUTO') {
        $script:RbEverything.Checked = $true
        $script:BtnChoose.Enabled = $false

        $list = if ($script:CachedRemoteEditions -and $script:CachedRemoteEditions.Count -gt 0) {
            $script:CachedRemoteEditions
        } elseif (-not [string]::IsNullOrWhiteSpace($script:Cfg.GamePath)) {
            @(Get-LocalEditions $script:Cfg.GamePath)
        } else {
            @()
        }

        if ($list.Count -gt 0) {
            $dispList = $list | ForEach-Object { Format-EditionDisplay $_ }
            $script:LblTracking.Text = T 'gui.tracking_auto'
            if ($null -ne $script:TxtTracking) {
                $script:TxtTracking.Visible = $true
                $script:TxtTracking.Text = ($dispList -join "`r`n")
            }
        } else {
            $script:LblTracking.Text = T 'gui.tracking_auto'
            if ($null -ne $script:TxtTracking) {
                $script:TxtTracking.Visible = $true
                $script:TxtTracking.Text = (T 'gui.rb_everything')
            }
        }
    } else {
        $script:RbSpecific.Checked = $true
        $script:BtnChoose.Enabled = -not $script:Busy
        $list = @($script:Cfg.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($list.Count -eq 0) {
            $script:LblTracking.Text = T 'gui.tracking_none'
            if ($null -ne $script:TxtTracking) { $script:TxtTracking.Visible = $false }
        } else {
            $dispList = $list | ForEach-Object { Format-EditionDisplay $_ }
            $script:LblTracking.Text = T 'gui.tracking' @{ editions = "$($list.Count)" }
            if ($null -ne $script:TxtTracking) {
                $script:TxtTracking.Visible = $true
                $script:TxtTracking.Text = ($dispList -join "`r`n")
            }
        }
    }
}

function Apply-I18n {
    $script:Form.Text         = T 'gui.window_title'
    $script:LblLang.Text      = T 'gui.lang_label'
    $script:GrpFolder.Text    = T 'gui.group_folder'
    $script:BtnChange.Text    = T 'gui.btn_change'
    $script:GrpSongs.Text     = T 'gui.group_songs'
    $script:RbEverything.Text = T 'gui.rb_everything'
    $script:RbSpecific.Text   = T 'gui.rb_specific'
    $script:BtnChoose.Text    = T 'gui.btn_choose_editions'
    $script:BtnCheck.Text     = T 'gui.btn_check'
    $script:BtnExit.Text      = T 'gui.btn_exit'
    Refresh-FolderStatus
    Refresh-Tracking
}

function Set-Busy([bool]$On) {
    $script:Busy = $On
    $enabled = -not $On
    $script:BtnCheck.Enabled  = $enabled
    $script:BtnChange.Enabled = $enabled
    $script:RbEverything.Enabled = $enabled
    $script:RbSpecific.Enabled   = $enabled
    $script:CmbLang.Enabled   = $enabled
    $script:BtnChoose.Enabled = $enabled -and $script:RbSpecific.Checked
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
    # switched to "specific"
    $script:BtnChoose.Enabled = $true
    if ($script:Cfg.Editions.ToUpper() -eq 'AUTO') {
        $res = Show-EditionsDialog
        if ($null -eq $res -or $res -eq '' -or $res -eq 'AUTO') {
            # nothing chosen or all chosen -> fall back to Everything
            $script:RbEverything.Checked = $true
            return
        }
        Save-Config -GamePath $script:Cfg.GamePath -Editions $res
        $script:Cfg = Load-Config
    }
    Refresh-Tracking
}

function On-ChooseEditions {
    if (-not $script:Ready -or $script:Busy) { return }
    $res = Show-EditionsDialog
    if ($null -eq $res) { return }
    if ($res -eq '') { Warn-Box (T 'gui.no_editions_body') (T 'gui.err_title'); return }
    if ($res -eq 'AUTO') {
        Save-Config -GamePath $script:Cfg.GamePath -Editions 'AUTO'
        $script:Cfg = Load-Config
        $script:RbEverything.Checked = $true
        Refresh-Tracking
        return
    }
    Save-Config -GamePath $script:Cfg.GamePath -Editions $res
    $script:Cfg = Load-Config
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
    $script:Form.ClientSize = New-Object System.Drawing.Size(520, 580)
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
    $script:GrpSongs.SetBounds(12, 134, 496, 160)

    $script:RbEverything = New-Object System.Windows.Forms.RadioButton
    $script:RbEverything.Font = $script:FontBase
    $script:RbEverything.ForeColor = $script:ColorText
    $script:RbEverything.SetBounds(16, 22, 464, 22)

    $script:RbSpecific = New-Object System.Windows.Forms.RadioButton
    $script:RbSpecific.Font = $script:FontBase
    $script:RbSpecific.ForeColor = $script:ColorText
    $script:RbSpecific.SetBounds(16, 46, 190, 22)

    $script:BtnChoose = New-Btn '' 210 44 160 26 $false
    $script:BtnChoose.Add_Click({ param($s, $e) On-ChooseEditions })

    $script:LblTracking = New-Label '' 16 72 464 18
    $script:LblTracking.ForeColor = $script:ColorMuted

    $script:TxtTracking = New-Object System.Windows.Forms.TextBox
    $script:TxtTracking.Multiline = $true
    $script:TxtTracking.ReadOnly = $true
    $script:TxtTracking.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:TxtTracking.SetBounds(16, 92, 464, 58)
    $script:TxtTracking.Font = $script:FontBase
    $script:TxtTracking.BackColor = [System.Drawing.Color]::FromArgb(250, 251, 253)
    $script:TxtTracking.ForeColor = $script:ColorText
    $script:TxtTracking.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $script:RbEverything.Add_CheckedChanged({ param($s, $e) if ($script:RbEverything.Checked) { On-SongModeChanged } })
    $script:RbSpecific.Add_CheckedChanged({ param($s, $e) if ($script:RbSpecific.Checked) { On-SongModeChanged } })
    $script:GrpSongs.Controls.AddRange(@($script:RbEverything, $script:RbSpecific, $script:BtnChoose, $script:LblTracking, $script:TxtTracking))

    # Check for updates button (Primary CTA)
    $script:BtnCheck = New-Btn '' 12 302 496 38 $true
    $script:BtnCheck.Add_Click({ param($s, $e) On-Check })

    # Progress bar & Status
    $script:Bar = New-Object System.Windows.Forms.ProgressBar
    $script:Bar.SetBounds(12, 348, 496, 18)
    $script:Bar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:Bar.MarqueeAnimationSpeed = 30

    $script:LblProg = New-Label '' 12 370 496 18
    $script:LblProg.ForeColor = $script:ColorMuted

    # Activity Log
    $script:TxtLog = New-Object System.Windows.Forms.TextBox
    $script:TxtLog.Multiline = $true; $script:TxtLog.ReadOnly = $true
    $script:TxtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:TxtLog.SetBounds(12, 392, 496, 140)
    $script:TxtLog.Font = $script:FontMono
    $script:TxtLog.BackColor = $script:ColorCard
    $script:TxtLog.ForeColor = $script:ColorText
    $script:TxtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    # Exit Button
    $script:BtnExit = New-Btn '' 418 540 90 28 $false
    $script:BtnExit.Add_Click({ param($s, $e) $script:Form.Close() })

    $script:Form.Controls.AddRange(@(
            $script:LblLang, $script:CmbLang,
            $script:GrpFolder, $script:GrpSongs,
            $script:BtnCheck, $script:Bar, $script:LblProg, $script:TxtLog, $script:BtnExit
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
    $script:Form.Dispose()
    Write-Host "`nSELFTEST OK"
    return
}

[System.Windows.Forms.Application]::Run($script:Form)
