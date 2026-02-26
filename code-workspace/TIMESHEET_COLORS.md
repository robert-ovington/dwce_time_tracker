# Colors Used in Timesheet Screen

## Custom Hex Colors

1. **`Color(0xFF0081FB)`** - Primary Blue
   - Hex: `#0081FB`
   - Used for: AppBar background, buttons, icons, borders
   - Usage: Main brand color throughout the screen

2. **`Color(0xFFFEFE00)`** - Yellow Accent
   - Hex: `#FEFE00`
   - Used for: AppBar bottom border (yellow accent strip)
   - Usage: Brand accent color

3. **`Color(0xFF005AB0)`** - Dark Blue Border
   - Hex: `#005AB0`
   - Used for: Border colors, section dividers
   - Usage: Darker blue for borders and dividers

4. **`Color(0xFFBADDFF)`** - Light Blue Background
   - Hex: `#BADDFF`
   - Used for: Container backgrounds, section backgrounds
   - Usage: Light blue background for containers and sections

## Named Colors (Material Colors)

### Red
- `Colors.red` - Standard red
- `Colors.red.shade50` - Very light red (for invalid input backgrounds)
- `Colors.red.shade700` - Dark red (for text, borders)
- `Colors.red.withOpacity(0.1)` - Semi-transparent red (for date backgrounds)

### Green
- `Colors.green` - Standard green
- `Colors.green.shade50` - Very light green (for online indicator background)
- `Colors.green.shade700` - Dark green (for text, status indicators)
- `Colors.green.withOpacity(0.1)` - Semi-transparent green (for current date background)

### Orange
- `Colors.orange` - Standard orange
- `Colors.orange.shade50` - Very light orange (for offline indicator background)
- `Colors.orange.shade700` - Dark orange (for text, status indicators)
- `Colors.orange.withOpacity(0.1)` - Semi-transparent orange (for offline date background)

### Blue
- `Colors.blue` - Standard blue
- `Colors.blue.shade700` - Dark blue (for text, links)

### Grey
- `Colors.grey` - Standard grey
- `Colors.grey.shade50` - Very light grey (for backgrounds)
- `Colors.grey.shade100` - Light grey (for backgrounds, borders)
- `Colors.grey.shade300` - Medium grey (for borders)
- `Colors.grey.shade600` - Medium-dark grey (for text)
- `Colors.grey.shade700` - Dark grey (for text, icons)
- `Colors.grey.withOpacity(0.1)` - Semi-transparent grey (for date backgrounds)

### White
- `Colors.white` - Pure white
- Used for: Text field fill colors, card backgrounds, button text

### Black
- `Colors.black` - Pure black
- `Colors.black87` - 87% opacity black (for text)

### Yellow
- `Colors.yellow` - Standard yellow
- Used for: Button foreground (on blue background)

## Color Usage by Context

### Status Indicators
- **Online**: `Colors.green.shade50` (background), `Colors.green` (icon), `Colors.green.shade700` (text)
- **Offline**: `Colors.orange.shade50` (background), `Colors.orange` (icon), `Colors.orange.shade700` (text)

### Date Selection
- **Current Date**: `Colors.green.withOpacity(0.1)` (background), `Colors.green` (text)
- **Past Dates**: `Colors.red.withOpacity(0.1)` (background), `Colors.red` (text)
- **Future Dates**: `Colors.grey.withOpacity(0.1)` (background), `Colors.grey` (text)
- **Offline Mode Dates**: `Colors.orange.withOpacity(0.1)` (background)

### Buttons
- **Primary Actions**: `Color(0xFF0081FB)` (background), `Colors.white` (text)
- **Success/Submit**: `Colors.green` (background), `Colors.white` (text)
- **Warning/Cancel**: `Colors.orange` (background), `Colors.white` or `Colors.black` (text)
- **Delete/Danger**: `Colors.red` (background), `Colors.white` (text)
- **Special Buttons**: `Colors.blue` (background), `Colors.yellow` (text)

### Input Fields
- **Valid Input**: `Colors.white` (fill), `Colors.grey.shade300` (border)
- **Invalid Input**: `Colors.red.shade50` (fill), `Colors.red` (border, 2px width)
- **Normal Text**: `Colors.black87` or `Colors.grey.shade700`
- **Placeholder/Disabled**: `Colors.grey`

### Borders and Dividers
- **Primary Border**: `Color(0xFF005AB0)` (2px width)
- **Section Divider**: `Color(0xFF005AB0)` (bottom border, 2px width)
- **Input Border**: `Colors.grey.shade300`
- **Error Border**: `Colors.red` (2px width)

### Backgrounds
- **Main Container**: `Color(0xFFBADDFF)` (light blue)
- **Fleet Mode Container**: `Colors.red.withOpacity(0.1)` (reddish tint)
- **Section Background**: `Colors.grey.shade100` or `Colors.grey.shade50`
- **Card/White Background**: `Colors.white`

### Text Colors
- **Primary Text**: `Colors.black87`
- **Secondary Text**: `Colors.grey.shade700` or `Colors.grey.shade600`
- **Link Text**: `Color(0xFF0081FB)` or `Colors.blue.shade700`
- **Error Text**: `Colors.red` or `Colors.red.shade700`
- **Info Text**: `Colors.blue`

## Summary Count

- **Custom Hex Colors**: 4 unique colors
- **Named Material Colors**: 8 base colors (red, green, orange, blue, grey, white, black, yellow)
- **Color Shades/Variations**: Multiple shades (50, 100, 300, 600, 700) and opacity variations
- **Total Unique Color Values**: ~30+ distinct color values
