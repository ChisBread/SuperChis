# SuperChis

SuperChis is a open-source CPLD implementation project designed to reverse engineer and understand the principles behind the original SuperCard flash cartridge for Game Boy Advance. This project provides complete VHDL source code and associated development tools for educational and research purposes.

## Project Features

- 🔧 **Open Source**: Complete VHDL source code and hardware design files
- 🔍 **Reverse Engineering**: Aims to understand and replicate SuperCard functionality
- 🎮 **GBA Compatible**: Compatibility with Game Boy Advance and NDS
- 💾 **Multi-Storage Support**: DDR SDRAM, Flash memory, and SRAM support
- 💾 **SD Card Interface**: Integrated SD card interface for mass storage
- 🛠️ **Configurable**: Flexible configuration options and memory mapping

## Hardware Architecture

### Main Components
- **CPLD Controller**: Implements GBA interface protocol and memory control logic
- **DDR SDRAM**: High-speed dynamic RAM for large capacity data storage
- **Flash Memory**: Non-volatile memory for ROM data storage
- **SRAM**: Static RAM for save data
- **SD Card Interface**: External storage expansion support

### Interface Description
- **GBA Interface**: 16-bit data bus + 8-bit address bus
- **Memory Interface**: Unified interface supporting multiple memory types
- **Configuration Interface**: System configuration through special addresses

## File Structure

```
├── superchis.vhd      # Main VHDL design file
└── README.md         # Project documentation
```

## License

This project is released under an open source license. Please see the LICENSE file in the project root for specific license information.

## References

1. [gba-supercard-cpld](https://github.com/davidgfnet/gba-supercard-cpld) - Original CPLD implementation reference
2. [SuperFW](https://github.com/davidgfnet/superfw) - SuperCard firmware reference
3. GBA technical documentation and hardware specifications
4. DDR SDRAM controller design references
