<#
.SYNOPSIS
    Plays a random theme song from a curated list of 1990's television shows and movies.

.DESCRIPTION
    The script emits an attention-grabbing console beep sequence and then streams a random
    1990's theme song or movie anthem using the .NET MediaPlayer class.  Audio is sourced
    from publicly available MP3 files and played directly from their URLs—no temporary
    download is required.  A fallback option is included when streaming is unavailable.

.PARAMETER Volume
    Sets the playback volume as a value between 0.0 (muted) and 1.0 (maximum).

.PARAMETER Loop
    Repeats playback indefinitely until the user presses Ctrl+C.

.PARAMETER List
    Displays the curated soundtrack list without playing audio.

.EXAMPLE
    # Play a single random theme song at 60% volume
    .\Play-90sThemeSongs.ps1 -Volume 0.6

.EXAMPLE
    # Continuously play random tracks
    .\Play-90sThemeSongs.ps1 -Loop
#>
[CmdletBinding()]
param(
    [ValidateRange(0.0, 1.0)]
    [double]$Volume = 0.75,

    [switch]$Loop,

    [switch]$List
)

$themeSongs = @(
    [pscustomobject]@{
        Title = 'The X-Files (1993)'
        Source = 'https://archive.org/download/TVThemeSongs/The%20X-Files%20-%20Theme.mp3'
        Duration = 121
    }
    [pscustomobject]@{
        Title = 'Friends (1994)'
        Source = 'https://archive.org/download/tvtunes_219/TV%20Tunes%20-%20Friends.mp3'
        Duration = 44
    }
    [pscustomobject]@{
        Title = 'Buffy the Vampire Slayer (1997)'
        Source = 'https://archive.org/download/tvtunes_234/TV%20Tunes%20-%20Buffy%20the%20Vampire%20Slayer.mp3'
        Duration = 88
    }
    [pscustomobject]@{
        Title = 'Teenage Mutant Ninja Turtles (1990)'
        Source = 'https://archive.org/download/tvtunes_148/TV%20Tunes%20-%20Teenage%20Mutant%20Ninja%20Turtles.mp3'
        Duration = 85
    }
    [pscustomobject]@{
        Title = 'Jurassic Park (1993)'
        Source = 'https://archive.org/download/MovieThemes/Jurassic%20Park.mp3'
        Duration = 206
    }
    [pscustomobject]@{
        Title = 'The Fresh Prince of Bel-Air (1990)'
        Source = 'https://archive.org/download/tvtunes_108/TV%20Tunes%20-%20Fresh%20Prince%20of%20Bel-Air.mp3'
        Duration = 110
    }
    [pscustomobject]@{
        Title = 'Batman: The Animated Series (1992)'
        Source = 'https://archive.org/download/tvtunes_168/TV%20Tunes%20-%20Batman%20The%20Animated%20Series.mp3'
        Duration = 63
    }
    [pscustomobject]@{
        Title = 'Star Trek: The Next Generation (1990s syndication)'
        Source = 'https://archive.org/download/tvtunes_237/TV%20Tunes%20-%20Star%20Trek%20-%20The%20Next%20Generation.mp3'
        Duration = 108
    }
    [pscustomobject]@{
        Title = 'Mission: Impossible (1996 film)'
        Source = 'https://archive.org/download/tvtunes_741/TV%20Tunes%20-%20Mission%20Impossible.mp3'
        Duration = 209
    }
    [pscustomobject]@{
        Title = 'The Mighty Morphin Power Rangers (1993)'
        Source = 'https://archive.org/download/tvtunes_860/TV%20Tunes%20-%20Mighty%20Morphin%20Power%20Rangers.mp3'
        Duration = 72
    }
)

if ($List) {
    Write-Host '1990s Theme Song Playlist:' -ForegroundColor Cyan
    $themeSongs | ForEach-Object {
        Write-Host " - $($_.Title)" -ForegroundColor Yellow
    }
    return
}

function Invoke-ConsoleFanFare {
    $melody = @(
        @{Frequency = 784; Duration = 200},
        @{Frequency = 880; Duration = 200},
        @{Frequency = 988; Duration = 300},
        @{Frequency = 1319; Duration = 400}
    )

    foreach ($note in $melody) {
        try {
            [Console]::Beep($note.Frequency, $note.Duration)
        } catch {
            Start-Sleep -Milliseconds $note.Duration
        }
    }
}

function Get-RandomThemeSong {
    return Get-Random -InputObject $themeSongs
}

function New-MediaPlayer {
    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        return New-Object System.Windows.Media.MediaPlayer
    } catch {
        Write-Warning 'MediaPlayer could not be initialized. Streaming playback is unavailable.'
        return $null
    }
}

function Invoke-Playback {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Media.MediaPlayer]$Player,

        [Parameter(Mandatory)]
        [pscustomobject]$Track
    )

    $Player.Open([Uri]$Track.Source)
    $Player.Volume = [Math]::Max(0.0, [Math]::Min(1.0, $Volume))
    $Player.Play()
    Write-Host "Now playing: $($Track.Title)" -ForegroundColor Green

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $target = [TimeSpan]::FromSeconds($Track.Duration)

    while ($stopwatch.Elapsed -lt $target) {
        Start-Sleep -Milliseconds 250
    }

    $Player.Stop()
}

$player = New-MediaPlayer

if (-not $player) {
    Write-Warning 'Falling back to console fanfare because no media player is available.'
    Invoke-ConsoleFanFare
    return
}

try {
    do {
        $track = Get-RandomThemeSong
        Invoke-ConsoleFanFare
        Invoke-Playback -Player $player -Track $track
        if ($Loop) {
            Write-Host 'Press Ctrl+C to exit, selecting another track...' -ForegroundColor DarkGray
        }
    } while ($Loop)
} finally {
    $player.Close()
}
