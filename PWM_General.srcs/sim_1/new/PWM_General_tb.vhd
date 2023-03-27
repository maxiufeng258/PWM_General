----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2023/03/19 14:01:56
-- Design Name: 
-- Module Name: PWM_General_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
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

entity PWM_General_tb is
--  Port ( );
end PWM_General_tb;

architecture Behavioral of PWM_General_tb is
component PWM_General is
    Generic (
        SYS_CLK_VAL_HZ      :   integer := 40_000_000;  -- ϵͳ������ʱ��ֵ ��λ��Hz
        WORK_MODE           :   std_logic := '0';
        PWM_CH_Polarity     :   std_logic := '1';       -- PWM���ͨ�����ʱ��ռ�ձ�(PWMģʽCNT<CR)-��Ӧ��ϵ: 1->��,0->��
        PWM_CH_Idle_State   :   std_logic := '0'        -- PWM���ڿ���ʱ��ͨ���ĵ�ƽ״̬
    );
    Port (
        i_SysClk    :   in      std_logic;  -- ϵͳʱ��
        i_SysNrst   :   in      std_logic;  -- ϵͳ�첽��λ
        i_EN        :   in      std_logic;  -- ϵͳ����ģ�鹤��λ ģ��ʹ�ܣ�1�����ã�0
        
        i_PwmParamUpdateFlag : in   std_logic;
        i_PwmFreqHz :   in      integer range 0 to 100_000; -- �������õ���1-100KHz��Ƶ��������
        i_PwmCompVal:   in      integer range 0 to 50_000_000; -- ���ֵ�����ֵ(SYS_CLK_VAL_HZ/i_PwmFreqHz)���Ƚ�
        
        o_PWM_CH       :   out     std_logic; -- PWM ���
        o_PWM_CHN      :    out   std_logic;
        
        o_CRUIE     :   out     std_logic
    );
end component; 

    signal  sysClk  :   std_logic := '0';
    signal  sysNrst :   std_logic := '0';
    signal  EN      :   std_logic := '0';
    signal  paramSet:   std_logic := '0';
    signal  PWM     :   std_logic;
    signal  PWMN    :   std_logic;
    signal  halfCLK :   time := 10ns;
    signal  pwmFreq :   integer := 0;
    signal  pwmComp :   integer := 0;
    signal  cruie   :   std_logic;
    type t_fsm  is (s1,s2,s3,s4,s5);
    signal s_fsm : t_fsm := s1;
begin
    clk: process
    begin
        sysClk <= '0';
        wait for halfCLK;
        sysCLK <= '1';
        wait for halfCLK;
    end process;
    
    nrst :process
    begin
        sysNrst <= '0';
        wait for 35ns;
        sysNrst <= '1';
        wait;
    end process;
    
--    proc :process
--    begin
--        EN <= '1';
--        paramSet <= '0';
--        wait for 58ns;
--        paramSet <= '1';
--        pwmFreq <= 200000;
--        pwmComp <= 50000000/400000;
--        wait for 22ns;

--        wait for 35ns;
--        paramSet <= '0';
--        --wait for 5ms;
--        --EN <= '0';
--        wait for 4ms;

--        paramSet <= '1';
--        pwmFreq <= 100000;
--        pwmComp <= 50000000/200000;
--        wait for 30ns;
--        paramSet <= '0';
--        wait for 20ms;
--        wait;
--    end process;

    process (sysClk, sysNrst)
    begin
        if (sysNrst = '0') then
            EN <= '0';
            pwmFreq <= 0;
            pwmComp <= 0;
            paramSet <= '0';
            s_fsm <= s1;
        elsif (rising_edge(sysCLk)) then
            case s_fsm is
                when s1 =>
                    EN <= '1';
                    pwmFreq <= 1_000_000;
                    pwmComp <= 25;
                    paramSet <= '1';
                    s_fsm <= s2;
                when s2 =>
                    paramSet <= '0';
                    s_fsm <= s3;
                when s3 =>
                    if (cruie = '1') then
--                        if (pwmComp = 105) then
--                            EN <= '0';
--                        elsif (pwmComp < 480) then
--                            pwmComp <= pwmComp + 20;
--                        else
--                            pwmCOmp <= pwmComp;
--                        end if;
                        -- �Ƚ�ģʽ
                        pwmComp <= 10;
                        -- �Ƚ�ģʽ����
                        paramSet <= '1';
                        s_fsm <= s4;
                    end if;
                when s4 =>
                    s_fsm <= s3;
                    paramSet <= '0';
                when others =>
            end case;
        end if;
    end process;
    
    -------------------------------------------------------
    PWM_Module:  PWM_General 
    Generic map (
        SYS_CLK_VAL_HZ      => 50_000_000,  -- 50MHz  ϵͳ����ʱ��ֵ ��λ��Hz
        WORK_MODE           => '0', -- '0'->PWMģʽ��'1'->����Ƚ�ģʽ
        PWM_CH_Polarity     => '1',   -- PWM���ͨ�����ʱ��ռ�ձȶ�Ӧ��ϵ: 1->��,0->��
        PWM_CH_Idle_State   => '0'    -- PWM���ڿ���ʱ��ͨ���ĵ�ƽ״̬
    )
    Port map (
        i_SysClk    => sysClk,  -- ϵͳʱ��
        i_SysNrst   => sysNrst,  -- ϵͳ�첽��λ
        i_EN        => EN,  -- ϵͳ����ģ�鹤��λ ģ��ʹ�ܣ�1�����ã�0
        
        i_PwmParamUpdateFlag => paramSet,
        i_PwmFreqHz  => pwmFreq, -- �������õ���1-100KHz��Ƶ��������
        i_PwmCompVal => pwmComp, -- ���ֵ�����ֵ(SYS_CLK_VAL_HZ/i_PwmFreqHz)���Ƚ�
        
        o_PWM_CH        => PWM , -- PWM ���
        o_PWM_CHN       => PWMN,
        o_CRUIE     => cruie
    );

end Behavioral;
