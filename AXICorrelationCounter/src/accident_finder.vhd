----------------------------------------------------------------------------------
-- Correlation accident finder
-- Version: 1.0
--
-- Authors: Daniel Martinez / Cedric Leonard
-- Created: 28.2.2024
-- 28.2.2024 -> First draft
--
-- Verify the events that happened on which channel, and 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity accident_finder is
    Port (
        correl : in STD_LOGIC_VECTOR (5 downto 0);
        enable : in STD_LOGIC;
        accident : out STD_LOGIC
    );
end accident_finder;


architecture RTL of accident_finder is -- not sure about architecture type
    
    -- Function to count the number of '1' bits in a vector
    function bit_count(v : STD_LOGIC_VECTOR) return integer is
        variable count : integer := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;

begin
    process (clk)
    begin
        if enable:
            -- Check if there is exactly 2 bits at 1 in correl: accident is set to 0
            if bit_count(correl) = 2 then
                accident <= '0';
            -- Else (only the main hit), or 3 or more hits in total: accident is set to 1
            else
                accident <= '1';
            end if;
        end if;
    end process;
end RTL;
