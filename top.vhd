-- GBA SuperCard CPLD Implementation
-- Based on LC4128x_TQFP128 CPLD Report Analysis

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity GBA_SUPERCARD_CPLD is
    Port (
        -- GBA Interface Bus
        GP_0 : inout STD_LOGIC;
        GP_1 : inout STD_LOGIC;
        GP_2 : inout STD_LOGIC;  
        GP_3 : inout STD_LOGIC;
        GP_4 : inout STD_LOGIC;
        GP_5 : inout STD_LOGIC;
        GP_6 : inout STD_LOGIC;
        GP_7 : inout STD_LOGIC;
        GP_8 : inout STD_LOGIC;
        GP_9 : inout STD_LOGIC;
        GP_10 : inout STD_LOGIC;
        GP_11 : inout STD_LOGIC;
        GP_12 : inout STD_LOGIC;
        GP_13 : inout STD_LOGIC;
        GP_14 : inout STD_LOGIC;
        GP_15 : inout STD_LOGIC;
        GP_16 : inout STD_LOGIC;
        GP_17 : inout STD_LOGIC;
        GP_18 : inout STD_LOGIC;
        GP_19 : inout STD_LOGIC;
        GP_20 : inout STD_LOGIC;
        GP_21 : inout STD_LOGIC;
        GP_22 : inout STD_LOGIC;
        GP_23 : inout STD_LOGIC;
        
        -- Control Signals
        GP_NCS : in STD_LOGIC;    -- Chip Select (active low)
        GP_NRD : in STD_LOGIC;    -- Read Enable (active low)
        GP_NWR : in STD_LOGIC;    -- Write Enable (active low)
        
        -- DDR SDRAM Interface
        DDR_A0 : out STD_LOGIC;
        DDR_A1 : out STD_LOGIC;
        DDR_A2 : out STD_LOGIC;
        DDR_A3 : out STD_LOGIC;
        DDR_A4 : out STD_LOGIC;
        DDR_A5 : out STD_LOGIC;
        DDR_A6 : out STD_LOGIC;
        DDR_A7 : out STD_LOGIC;
        DDR_A8 : out STD_LOGIC;
        DDR_A9 : out STD_LOGIC;
        DDR_A10 : out STD_LOGIC;
        DDR_A11 : out STD_LOGIC;
        DDR_A12 : out STD_LOGIC;
        DDR_BA0 : out STD_LOGIC;
        DDR_BA1 : out STD_LOGIC;
        DDR_CAS : out STD_LOGIC;
        DDR_RAS : out STD_LOGIC;
        DDR_WE : out STD_LOGIC;
        DDR_CKE : out STD_LOGIC;
        DDR_CLK : out STD_LOGIC;
        DDR_DM0 : out STD_LOGIC;
        DDR_DM1 : out STD_LOGIC;
        
        -- Flash Memory Interface
        FLASH_A0 : out STD_LOGIC;
        FLASH_A1 : out STD_LOGIC;
        FLASH_A2 : out STD_LOGIC;
        FLASH_A3 : out STD_LOGIC;
        FLASH_A4 : out STD_LOGIC;
        FLASH_A5 : out STD_LOGIC;
        FLASH_A6 : out STD_LOGIC;
        FLASH_A7 : out STD_LOGIC;
        FLASH_A8 : out STD_LOGIC;
        FLASH_A9 : out STD_LOGIC;
        FLASH_A10 : out STD_LOGIC;
        FLASH_A11 : out STD_LOGIC;
        FLASH_A12 : out STD_LOGIC;
        FLASH_A13 : out STD_LOGIC;
        FLASH_A14 : out STD_LOGIC;
        FLASH_A15 : out STD_LOGIC;
        FLASH_A16 : out STD_LOGIC;
        FLASH_A17 : out STD_LOGIC;
        FLASH_A18 : out STD_LOGIC;
        FLASH_A19 : out STD_LOGIC;
        FLASH_SRAM_NOE : out STD_LOGIC;
        FLASH_SRAM_NWE : out STD_LOGIC;
        FLASH_NCE : out STD_LOGIC;
        
        -- SD Card Interface
        SD_CLK : out STD_LOGIC;
        SD_CMD : inout STD_LOGIC;
        SD_DAT0 : inout STD_LOGIC;
        SD_DAT1 : inout STD_LOGIC;
        SD_DAT2 : inout STD_LOGIC;
        SD_DAT3 : inout STD_LOGIC;
        
        -- Other Control
        SRAM_A16 : out STD_LOGIC;
        N_SDOUT : out STD_LOGIC;
        MAP_REG : out STD_LOGIC;
        N_DDR_SEL : out STD_LOGIC
    );
end GBA_SUPERCARD_CPLD;

architecture Behavioral of GBA_SUPERCARD_CPLD is
    
    -- Internal State Machine Signals  
    signal mc_A0, mc_A1, mc_A2, mc_A5 : STD_LOGIC := '0';
    signal mc_B5, mc_B6, mc_B9, mc_B10, mc_B13, mc_B14, mc_B15 : STD_LOGIC := '0';
    signal mc_C0, mc_C1, mc_C8, mc_C9, mc_C10, mc_C13, mc_C14 : STD_LOGIC := '0';
    signal mc_D9, mc_D10 : STD_LOGIC := '0';
    signal mc_E0, mc_E2, mc_E3, mc_E6, mc_E7 : STD_LOGIC := '0';
    signal mc_F0, mc_F1, mc_F5, mc_F12, mc_F15 : STD_LOGIC := '0';
    signal mc_G1, mc_G2, mc_G4, mc_G12, mc_G14 : STD_LOGIC := '0';
    signal mc_H0, mc_H1, mc_H2, mc_H3, mc_H5, mc_H6, mc_H7, mc_H8, mc_H9 : STD_LOGIC := '0';
    signal mc_H10, mc_H11, mc_H13, mc_H14, mc_H15 : STD_LOGIC := '0';
    
    -- DDR Counter Signals
    signal ddrcnt0, ddrcnt1, ddrcnt2, ddrcnt3 : STD_LOGIC := '0';
    
    -- Internal Counter Signals (9-bit counter)
    signal icntr0, icntr1, icntr2, icntr3, icntr4 : STD_LOGIC := '0';
    signal icntr5, icntr6, icntr7, icntr8 : STD_LOGIC := '0';
    
    -- Flash Address Counter
    signal iaddr_a0, iaddr_a1, iaddr_a2, iaddr_a3, iaddr_a4, iaddr_a5, iaddr_a6, iaddr_a7 : STD_LOGIC := '0';
    signal iaddr_a8, iaddr_a9, iaddr_a10, iaddr_a11, iaddr_a12, iaddr_a13, iaddr_a14, iaddr_a15 : STD_LOGIC := '0';
    
    -- Control Signals
    signal SDENABLE, WRITEENABLE, FLASHCARDSEL : STD_LOGIC := '0';
    signal MAGICADDR, LOAD_IREG, addr_load : STD_LOGIC := '0';
    
begin

    -- Pin Assignments based on Report
    
    -- DDR Address Mapping
    DDR_A2 <= mc_A0;
    DDR_A3 <= mc_A1; 
    DDR_A5 <= mc_A2;
    DDR_A4 <= ddrcnt1;
    DDR_A6 <= ddrcnt2;
    DDR_A7 <= ddrcnt3;
    DDR_A8 <= ddrcnt0;
    DDR_A9 <= '0';  -- Connect as needed
    DDR_A10 <= '0'; -- Connect as needed
    
    -- DDR Control  
    DDR_RAS <= mc_B13;
    DDR_CAS <= mc_B14; 
    DDR_WE <= mc_B10;
    DDR_CKE <= '1';
    DDR_CLK <= GP_NCS;
    
    -- Flash Address Mapping
    FLASH_A0 <= iaddr_a0;
    FLASH_A1 <= iaddr_a1;
    FLASH_A2 <= iaddr_a2;
    FLASH_A3 <= iaddr_a3;
    FLASH_A4 <= iaddr_a4;
    FLASH_A5 <= iaddr_a2;  -- Per report equation
    FLASH_A6 <= iaddr_a6;
    FLASH_A7 <= iaddr_a7;
    FLASH_A8 <= iaddr_a8;
    FLASH_A9 <= mc_E7;
    FLASH_A10 <= iaddr_a10;
    FLASH_A11 <= iaddr_a11;
    FLASH_A12 <= iaddr_a12;
    FLASH_A13 <= iaddr_a13;
    FLASH_A14 <= iaddr_a14;
    FLASH_A15 <= iaddr_a15;
    
    -- Flash Control
    FLASH_NCE <= mc_E6;
    FLASH_SRAM_NOE <= GP_NRD;
    FLASH_SRAM_NWE <= GP_NWR;
    
    -- SD Card Interface  
    SD_CLK <= mc_H1;
    SD_CMD <= mc_H8;
    SD_DAT0 <= mc_H9;
    SD_DAT1 <= mc_H7;
    SD_DAT2 <= mc_H13;
    SD_DAT3 <= mc_H6;
    
    -- Other Control Signals
    SRAM_A16 <= WRITEENABLE;
    MAP_REG <= GP_0 when LOAD_IREG = '1' else MAP_REG;
    N_SDOUT <= GP_NCS or not GP_23 or not SDENABLE or MAGICADDR;
    N_DDR_SEL <= '0'; -- Active when DDR is selected
    
    -- Bidirectional Bus Control
    GP_12 <= mc_G4 when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP_13 <= (GP_22 or mc_F15) when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP_14 <= (GP_22 or mc_F0) when (not GP_NRD and not N_SDOUT) = '1' else 'Z';
    GP_15 <= (GP_22 or mc_F1) when (not GP_NRD and not N_SDOUT) = '1' else 'Z';

    -- GLB 0 (A) - DDR Address Generation Process
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- DDR Counter Implementation (per report equations)
            -- ddrcnt1 Toggle FF: ddrcnt1.T = !mc_A5 & ddrcnt0 & mc_B5 & !mc_B6 & !mc_B9
            if (not mc_A5 and ddrcnt0 and mc_B5 and not mc_B6 and not mc_B9) = '1' then
                ddrcnt1 <= not ddrcnt1;
            end if;
            
            -- ddrcnt0 D FF: ddrcnt0.D = (!mc_A5 & mc_B5 & !mc_B6 & !mc_B9) ^ ddrcnt0
            ddrcnt0 <= (not mc_A5 and mc_B5 and not mc_B6 and not mc_B9) xor ddrcnt0;
            
            -- ddrcnt2 Toggle FF: ddrcnt2.T = ddrcnt1 & !mc_A5 & ddrcnt0 & mc_B5 & !mc_B6 & !mc_B9
            if (ddrcnt1 and not mc_A5 and ddrcnt0 and mc_B5 and not mc_B6 and not mc_B9) = '1' then
                ddrcnt2 <= not ddrcnt2;
            end if;
            
            -- ddrcnt3 Toggle FF: ddrcnt3.T = ddrcnt1 & !mc_A5 & ddrcnt0 & ddrcnt2 & mc_B5 & !mc_B6 & !mc_B9
            if (ddrcnt1 and not mc_A5 and ddrcnt0 and ddrcnt2 and mc_B5 and not mc_B6 and not mc_B9) = '1' then
                ddrcnt3 <= not ddrcnt3;
            end if;
            
            -- Other DDR control logic
            mc_A0 <= (mc_A0 and mc_A5 and not mc_B6 and not mc_B9) or 
                     (not mc_A5 and not mc_B5 and mc_B9);
            
            mc_A1 <= (mc_A1 and mc_A5 and not mc_B6 and not mc_B9) or
                     (not mc_A5 and not mc_B5 and mc_B9);
            
            mc_A2 <= (mc_A2 and mc_A5 and mc_B6) or (mc_A2 and mc_A5 and mc_B9);
        end if;
    end process;
    
    -- GLB 1 (B) - DDR Control State Machine
    process(GP_NCS)
    begin  
        if rising_edge(GP_NCS) then
            -- DDR Control State Machine Logic
            mc_B5 <= (not mc_A5 and not mc_B9 and icntr8 and icntr7) xor (mc_A5 and mc_B6);
            
            mc_B6 <= (not mc_B5 and not mc_B6 and mc_E3 and mc_H0) or 
                     (not mc_A5 and not mc_B9 and not icntr7);
            
            mc_B9 <= (not mc_A5 or mc_B5 or mc_B6 or not mc_E3 or not mc_H0) and
                     (mc_B5 or mc_B9);
            
            -- DDR Write Enable
            mc_B10 <= (mc_A5 or mc_B5 or not mc_B6 or not mc_B9 or mc_E3) and
                      (not mc_A5 or mc_B6 or mc_B9);
            
            -- DDR RAS/CAS Logic
            mc_B13 <= (mc_B5 and not mc_B6 and mc_B9) or (mc_B6 and not mc_B9);
            
            mc_B14 <= (mc_A5 and mc_B5 and mc_B9 and N_DDR_SEL and not icntr8) or
                      (not mc_B6 and mc_B9);
        end if;
    end process;

    -- GLB 6 (G) - Internal Counter Process  
    process(GP_NCS)
    begin
        if rising_edge(GP_NCS) then
            -- 9-bit internal counter (per report equations)
            -- icntr0 always toggles
            icntr0 <= not icntr0;
            
            -- icntr1.T = icntr0
            if icntr0 = '1' then
                icntr1 <= not icntr1;
            end if;
            
            -- icntr2.T = icntr1 & icntr0
            if (icntr1 and icntr0) = '1' then
                icntr2 <= not icntr2;
            end if;
            
            -- icntr3.T = icntr1 & icntr0 & icntr2
            if (icntr1 and icntr0 and icntr2) = '1' then
                icntr3 <= not icntr3;
            end if;
            
            -- icntr4.T = icntr1 & icntr0 & icntr3 & icntr2
            if (icntr1 and icntr0 and icntr3 and icntr2) = '1' then
                icntr4 <= not icntr4;
            end if;
            
            -- icntr5.T = icntr1 & icntr0 & icntr3 & icntr2 & icntr4
            if (icntr1 and icntr0 and icntr3 and icntr2 and icntr4) = '1' then
                icntr5 <= not icntr5;
            end if;
            
            -- icntr6.T = icntr1 & icntr0 & icntr5 & icntr3 & icntr2 & icntr4
            if (icntr1 and icntr0 and icntr5 and icntr3 and icntr2 and icntr4) = '1' then
                icntr6 <= not icntr6;
            end if;
            
            -- icntr7.T = icntr1 & icntr0 & icntr5 & icntr3 & icntr2 & icntr4 & icntr6
            if (icntr1 and icntr0 and icntr5 and icntr3 and icntr2 and icntr4 and icntr6) = '1' then
                icntr7 <= not icntr7;
            end if;
            
            -- icntr8.T = icntr1 & icntr0 & icntr5 & icntr3 & icntr2 & icntr7 & icntr4 & icntr6
            if (icntr1 and icntr0 and icntr5 and icntr3 and icntr2 and icntr7 and icntr4 and icntr6) = '1' then
                icntr8 <= not icntr8;
            end if;
        end if;
    end process;

    -- Flash Address Counter Process (GLB 2-5)
    process(mc_H11)
    begin
        if rising_edge(mc_H11) then
            -- Address counter logic based on report equations
            if addr_load = '1' then
                -- Load mode - addresses from GP bus
                iaddr_a0 <= GP_0;
                iaddr_a1 <= GP_1;
                iaddr_a2 <= GP_2;
                iaddr_a3 <= GP_3;
                iaddr_a4 <= GP_4;
                iaddr_a5 <= GP_5;
                iaddr_a6 <= GP_6;
                iaddr_a7 <= GP_7;
                iaddr_a8 <= GP_8;
                iaddr_a9 <= GP_9;
                iaddr_a10 <= GP_10;
                iaddr_a11 <= GP_11;
                iaddr_a12 <= GP_12;
                iaddr_a13 <= GP_13;
                iaddr_a14 <= GP_14;
                iaddr_a15 <= GP_15;
            else
                -- Counter mode - increment logic per report
                -- iaddr-a0.D = !iaddr-a0 & !addr-load | GP-0 & addr-load
                iaddr_a0 <= not iaddr_a0;
                
                -- iaddr-a1.D = !iaddr-a0 & iaddr-a1 & !addr-load | iaddr-a0 & !iaddr-a1 & !addr-load | GP-1 & addr-load
                iaddr_a1 <= (not iaddr_a0 and iaddr_a1) or (iaddr_a0 and not iaddr_a1);
                
                -- iaddr-a2.D complex equation from report
                iaddr_a2 <= (not iaddr_a2 and iaddr_a0 and iaddr_a1) or 
                           (iaddr_a2 and not iaddr_a0) or 
                           (iaddr_a2 and not iaddr_a1);
                
                -- Higher bits toggle based on carry chain
                if (iaddr_a2 and iaddr_a0 and iaddr_a1) = '1' then
                    iaddr_a3 <= not iaddr_a3;
                end if;
                
                if (iaddr_a2 and iaddr_a0 and iaddr_a1 and iaddr_a3) = '1' then
                    iaddr_a4 <= not iaddr_a4;
                end if;
                
                if (iaddr_a2 and iaddr_a4 and iaddr_a0 and iaddr_a1 and iaddr_a3) = '1' then
                    iaddr_a5 <= not iaddr_a5;
                end if;
                
                if (iaddr_a2 and iaddr_a4 and iaddr_a0 and iaddr_a5 and iaddr_a1 and iaddr_a3) = '1' then
                    iaddr_a6 <= not iaddr_a6;
                end if;
                
                -- Continue with higher bits...
                if (iaddr_a2 and iaddr_a4 and iaddr_a6 and iaddr_a0 and iaddr_a5 and iaddr_a1 and iaddr_a3) = '1' then
                    iaddr_a7 <= not iaddr_a7;
                end if;
                
                if (iaddr_a2 and iaddr_a4 and iaddr_a6 and iaddr_a0 and iaddr_a5 and iaddr_a1 and 
                    iaddr_a3 and iaddr_a7) = '1' then
                    iaddr_a8 <= not iaddr_a8;
                end if;
            end if;
        end if;
    end process;
    
    -- Register Load Process
    process(GP_NWR)
    begin
        if rising_edge(GP_NWR) then
            if LOAD_IREG = '1' then
                SDENABLE <= GP_1;
                WRITEENABLE <= GP_2;
                -- Load other configuration registers as needed
            end if;
        end if;
    end process;
    
    -- Control Signal Generation
    addr_load <= GP_NCS or (GP_NWR and GP_NRD and addr_load);
    mc_H11 <= (not GP_NCS and GP_NWR and GP_NRD) or (GP_NCS and not GP_NRD) or (GP_NCS and not GP_NWR);
    
    -- Magic Address Detection
    LOAD_IREG <= GP_4 and GP_6 and GP_7 and GP_8 and GP_9 and GP_14 and 
                GP_16 and GP_17 and GP_0 and GP_1 and GP_2 and GP_3 and GP_5 and 
                GP_10 and GP_11 and GP_18 and GP_22 and GP_21 and GP_20 and GP_19 and 
                GP_15 and GP_13 and GP_12 and GP_23;
    
    -- Additional control logic for other GLBs can be implemented as needed

end Behavioral;
