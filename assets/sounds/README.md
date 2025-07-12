# Water Sound Files

This directory contains sound files for water flow detection in the Water Monitor app.

## Required Sound Files

To enable water flow sounds, add the following MP3 files to this directory:

1. **water_flow.mp3** - Sound that plays when water starts flowing (looping ambient sound)
2. **water_stop.mp3** - Sound that plays when water stops flowing (one-time sound)
3. **notification.mp3** - Fallback notification sound (optional)

## Sound File Recommendations

### water_flow.mp3
- Duration: 2-5 seconds (will loop)
- Volume: Moderate (30% volume in app)
- Type: Gentle flowing water, stream, or fountain sound
- Format: MP3, 44.1kHz, 128-192kbps

### water_stop.mp3
- Duration: 1-2 seconds
- Volume: Slightly louder (50% volume in app)
- Type: Water drop, splash, or gentle stop sound
- Format: MP3, 44.1kHz, 128-192kbps

### notification.mp3
- Duration: 0.5-1 second
- Volume: Standard notification level
- Type: Simple beep or notification sound
- Format: MP3, 44.1kHz, 128kbps

## Free Sound Resources

You can find free water sounds from:
- Freesound.org
- Zapsplat.com
- Pixabay.com
- YouTube Audio Library

## File Naming

Make sure to use exactly these filenames:
- `water_flow.mp3`
- `water_stop.mp3`
- `notification.mp3`

## Testing

After adding the sound files:
1. Run `flutter pub get` to install dependencies
2. Rebuild the app
3. Go to Settings → Sound Settings to enable/disable sounds
4. Connect to your water monitoring device
5. Test by starting/stopping water flow

## Troubleshooting

If sounds don't play:
1. Check that files are in the correct directory (`assets/sounds/`)
2. Verify file names match exactly
3. Check app permissions for audio
4. Look at app logs for sound-related errors
5. Try the fallback notification sound first 