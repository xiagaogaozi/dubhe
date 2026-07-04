param(
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\app\resources')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-RoundedRectanglePath {
    param(
        [System.Drawing.RectangleF]$Rect,
        [float]$Radius
    )

    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $path.AddArc($Rect.X, $Rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-StarPoints {
    param(
        [float]$CenterX,
        [float]$CenterY,
        [float]$OuterRadius,
        [float]$InnerRadius
    )

    return @(
        [System.Drawing.PointF]::new($CenterX, $CenterY - $OuterRadius),
        [System.Drawing.PointF]::new($CenterX + $InnerRadius, $CenterY - $InnerRadius),
        [System.Drawing.PointF]::new($CenterX + $OuterRadius, $CenterY),
        [System.Drawing.PointF]::new($CenterX + $InnerRadius, $CenterY + $InnerRadius),
        [System.Drawing.PointF]::new($CenterX, $CenterY + $OuterRadius),
        [System.Drawing.PointF]::new($CenterX - $InnerRadius, $CenterY + $InnerRadius),
        [System.Drawing.PointF]::new($CenterX - $OuterRadius, $CenterY),
        [System.Drawing.PointF]::new($CenterX - $InnerRadius, $CenterY - $InnerRadius)
    )
}

function Write-DubhePng {
    param(
        [int]$Size,
        [string]$Path
    )

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $background = New-RoundedRectanglePath `
        -Rect ([System.Drawing.RectangleF]::new(0, 0, $Size, $Size)) `
        -Radius ([float]($Size * 0.22))
    $graphics.FillPath([System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#17231f')), $background)

    $dBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#8bd6ba'))
    $fontSize = [float]($Size * 0.62)
    $font = [System.Drawing.Font]::new('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = [System.Drawing.StringFormat]::new()
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textRect = [System.Drawing.RectangleF]::new([float]($Size * 0.07), [float]($Size * 0.08), [float]($Size * 0.76), [float]($Size * 0.78))
    $graphics.DrawString('D', $font, $dBrush, $textRect, $format)

    $starBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#f2c94c'))
    $star = New-StarPoints `
        -CenterX ([float]($Size * 0.73)) `
        -CenterY ([float]($Size * 0.28)) `
        -OuterRadius ([float]($Size * 0.12)) `
        -InnerRadius ([float]($Size * 0.045))
    $graphics.FillPolygon($starBrush, $star)

    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(210, 246, 251, 248), [float]([Math]::Max(1, $Size * 0.046)))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawBezier(
        $pen,
        [System.Drawing.PointF]::new([float]($Size * 0.24), [float]($Size * 0.80)),
        [System.Drawing.PointF]::new([float]($Size * 0.40), [float]($Size * 0.88)),
        [System.Drawing.PointF]::new([float]($Size * 0.62), [float]($Size * 0.87)),
        [System.Drawing.PointF]::new([float]($Size * 0.78), [float]($Size * 0.76))
    )

    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)

    $pen.Dispose()
    $format.Dispose()
    $font.Dispose()
    $dBrush.Dispose()
    $starBrush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    $background.Dispose()
}

function Write-Ico {
    param(
        [array]$Entries,
        [string]$Path
    )

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $writer = [System.IO.BinaryWriter]::new($stream)

    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$Entries.Count)

    $offset = 6 + ($Entries.Count * 16)
    foreach ($entry in $Entries) {
        $sizeByte = if ($entry.Size -eq 256) { 0 } else { $entry.Size }
        $writer.Write([byte]$sizeByte)
        $writer.Write([byte]$sizeByte)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$entry.Bytes.Length)
        $writer.Write([UInt32]$offset)
        $offset += $entry.Bytes.Length
    }

    foreach ($entry in $Entries) {
        $writer.Write($entry.Bytes)
    }

    $writer.Dispose()
    $stream.Dispose()
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$entries = foreach ($size in $sizes) {
    $path = Join-Path $OutputDir "icon-$size.png"
    Write-DubhePng -Size $size -Path $path
    [pscustomobject]@{
        Size = $size
        Bytes = [System.IO.File]::ReadAllBytes($path)
    }
}

Copy-Item -LiteralPath (Join-Path $OutputDir 'icon-256.png') -Destination (Join-Path $OutputDir 'icon.png') -Force
Write-Ico -Entries $entries -Path (Join-Path $OutputDir 'icon.ico')
