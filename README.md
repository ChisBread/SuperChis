# SuperChis

SuperChis is an open-source CPLD implementation project designed to understand the principles behind the original SuperCard-like flash carts used in the Game Boy Advance. The project provides complete VHDL source code for educational and research purposes.

## Project Features

- 🔧 **Open Source**: Complete VHDL source code and hardware design files
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

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)** license.

### What this means:

- ✅ **Educational and Research Use**: Free to use for learning, research, and educational purposes
- ✅ **Open Source**: Source code is freely available and can be modified
- ✅ **Attribution Required**: Must credit the original author when using or sharing
- ✅ **Share Alike**: Derivative works must use the same license
- ⚠️ **Commercial Use Restricted**: Commercial use requires separate licensing agreement

### Commercial Licensing

For commercial use, including manufacturing hardware or integrating into commercial products, please contact us for a separate commercial license agreement through GitHub Issues.

See the [LICENSE](LICENSE) file for complete license terms.

## References

1. [gba-supercard-cpld](https://github.com/davidgfnet/gba-supercard-cpld) - Original CPLD implementation reference
2. [SuperFW](https://github.com/davidgfnet/superfw) - SuperCard firmware reference
3. GBA technical documentation and hardware specifications
4. DDR SDRAM controller design references
