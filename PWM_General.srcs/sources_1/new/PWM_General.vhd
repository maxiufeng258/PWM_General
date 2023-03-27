----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Ma, Xiufeng
-- 
-- Create Date: 2023/03/19 13:35:10
-- Design Name: 
-- Module Name: PWM_General - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: vivado 2018
-- Description:  General purpose PWM(Pulse Width Modulation) Module
--               include PWM mode [set i_PwmFreqHz and i_PwmCompVal] [WORK_MODE = '0']
--                       OutputCompare mode [set i_PwmCompVal only]  [WORK_MODE = '1']
-- 
-- Dependencies: None
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

entity PWM_General is
    Generic (
        SYS_CLK_VAL_HZ      :   integer := 50_000_000;  -- ϵͳ������ʱ��ֵ ��λ��Hz
        
        WORK_MODE           :   std_logic := '0';   -- 0->PWM ����ģʽ
                                                     -- 1->OC(����Ƚ�) ����ģʽ
        
        PWM_CH_Polarity     :   std_logic := '1';   -- PWM���ͨ�����ʱ��ռ�ձ�(�״�CNT<CR�Ƚ�ʱ)-��Ӧ��ϵ:
                                                     -- 1->�ߣ�0->��
        PWM_CH_Idle_State   :   std_logic := '0'    -- ���ڿ���ʱ��ͨ���ĵ�ƽ״̬
                                                     -- 1->�ߣ�0->��
    );
    Port (
        i_SysClk    :   in      std_logic;  -- ϵͳʱ��
        i_SysNrst   :   in      std_logic;  -- ϵͳ�첽��λ
        i_EN        :   in      std_logic;  -- ϵͳ����ģ�鹤��λ ģ��ʹ�ܣ�1�����ã�0
        
        i_PwmParamUpdateFlag : in   std_logic;
        i_PwmFreqHz :   in      integer range 0 to 10_000_000; -- �������õ���1-100KHz��Ƶ�������� (��������SYS_CLK_VAL_HZ/i_PwmFreqHz)
        i_PwmCompVal:   in      integer range 0 to 50_000_000; -- ���ֵ�����ֵ(s_PwmCNT)���Ƚ�
        
        o_PWM_CH    :   out     std_logic;  -- PWM ���ͨ��
        o_PWM_CHN   :   out     std_logic;  -- PWM �������ͨ��
        
        o_CRUIE     :   out     std_logic   -- CNT���������ﵽCR�������� CR Update Interrupt Event ����
    );
end PWM_General; 

architecture Behavioral of PWM_General is
    -- ���峣��
    constant c_ValMax   :   integer := 50_000_000;  -- �趨s_PwmCR��s_PwmCNT�����
    -- �����źű���
    signal  s_PwmParamUpdateFlagSync : std_logic := '0'; --i_PwmParamUpdateFlag��ͬ���ź�
    signal  s_PwmParamUpdate :   std_logic := '0';            -- 0 ->����������Ч��ʹ��ԭ����������������(�״�����)��
                                                               -- 1 ->���������ã���i_EN=1,PWM���
    signal  s_PwmARR    :   integer range 0 to 50_000_000 := 0; -- PWM�Զ���װ��ֵ������ʱ�Ӻ�PWMƵ�ʾ���������PWMƵ��(����ʱ�Ӽ�������)
    signal  s_PwmCR     :   integer range 0 to 50_000_000 := 0; -- PWM�ȽϼĴ���������׼��
    signal  s_PwmCNT    :   integer range 0 to 50_000_000 := 0; -- PWM����������s_PwmCR�Ƚϴ���ת��s_PwmARR����������Χ
    
    type    t_FSM   is  (s_Idle, s_Work_PWM, s_Work_OC);
    signal  s_PwmFSM   :   t_FSM   :=  s_Idle;

    type    t_OC_FSM is (s_One, s_Two);
    signal  s_OC_FSM   :   t_OC_FSM:=  s_One;

begin
    -- ����߼�
    o_CRUIE <=  '0' when (i_PwmCompVal = 0 or s_PwmARR = 0 or s_PwmCR = s_PwmARR+1) and WORK_MODE = '0' and i_EN = '1' else
                '1' when s_PwmCNT = s_PwmCR and i_EN = '1' and WORK_MODE = '0' else
                '0' when i_PwmCompVal  = 0 and WORK_MODE = '1' and i_EN = '1' else
                '1' when (s_PwmCNT = s_PwmCR - 1 or s_PwmCNT = s_PwmCR + c_ValMax) and i_EN = '1' and WORK_MODE = '1' else
                '0';

    -- ˳���߼�
    main_proc: process (i_SysClk, i_SysNrst)
    -- �������
    variable v_PwmCR : integer range 0 to 50_000_000 := 0;
    
    begin
        if (i_SysNrst = '0') then
            s_PwmParamUpdateFlagSync      <= '0';
            s_PwmParamUpdate              <= '0';
            s_PwmARR                      <=  0 ;
            s_PwmCR                       <=  0 ;
            
            s_PwmCNT                      <=  0 ;
            
            s_PwmFSM                      <=  s_Idle;
            s_OC_FSM                      <=  s_One;
            
            o_PWM_CH                      <= PWM_CH_Idle_State;
            o_PWM_CHN                     <= not PWM_CH_Idle_State;
            
        elsif (rising_edge(i_SysClk)) then
            -- ���������ź����ɺͲ�����Ϣ����
            s_PwmParamUpdateFlagSync <= i_PwmParamUpdateFlag;
            if (i_PwmParamUpdateFlag = '0' and s_PwmParamUpdateFlagSync = '1' and s_PwmParamUpdate = '0' and i_EN = '1') then
                s_PwmParamUpdate    <= '1';
            else
                null;
            end if;
            
            -- ��״̬�����������
            case s_PwmFSM is
                when s_Idle =>        -- ����״̬���ȴ���������(�������ź�)
                    -- OFL
                    o_PWM_CH     <= PWM_CH_Idle_State;
                    o_PWM_CHN    <= not PWM_CH_Idle_State;

                    if (s_PwmParamUpdate = '1' and i_EN = '1') then
                        -- OFL
                        s_PwmParamUpdate    <= '0';
                        s_PwmARR            <= SYS_CLK_VAL_HZ / i_PwmFreqHz - 1; -- cnt������ֵ
                        s_PwmCR             <= i_PwmCompVal;   -- cnt�����ֵ���Ƚ�
                        -- NSL
                        if (WORK_MODE = '0') then
                            s_PwmFSM <= s_Work_PWM; -- ����PWM����ģʽ��CNT������ARR��CR����ռ�ձ�
                        else
                            s_PwmFSM <= s_Work_OC;  -- ��������Ƚ�ģʽ CNT��CR�Ƚϣ���ת
                            s_OC_FSM <= s_One;
                        end if;
                    elsif (i_EN = '0') then
                        s_PwmARR            <= 0;
                        s_PwmCR             <= 0;
                    else
                        s_PwmARR            <= s_PwmARR;
                        s_PwmCR             <= s_PwmCR;
                    end if;
                when s_Work_PWM =>        -- �����趨�������PWM�� (�������pwmƵ�ʺ�ռ�ձȲ���CR����)
                    -- SM
                    s_PwmFSM <= s_Work_PWM;
                
                    if (s_PwmCNT = s_PwmARR) then
                        -- CNT����
                        s_PwmCNT <= 0;
                        if (s_PwmCR = s_PwmARR+1) then
                            o_PWM_CH  <= PWM_CH_Polarity;
                            o_PWM_CHN <= not PWM_CH_Polarity;
                        else
                            o_PWM_CH  <= not PWM_CH_Polarity;
                            o_PWM_CHN <= PWM_CH_Polarity;
                        end if;

                        -- �������±�־��Ч
                        if (i_EN = '1') then
                            if (s_PwmParamUpdate = '1') then
                                s_PwmParamUpdate    <= '0';
                                s_PwmARR            <= SYS_CLK_VAL_HZ / i_PwmFreqHz - 1; -- cnt������ֵ
                                s_PwmCR             <= i_PwmCompVal;   -- cnt�����ֵ���Ƚ�
                            else
                                s_PwmARR            <= s_PwmARR; -- cnt������ֵ
                                s_PwmCR             <= s_PwmCR;  -- cnt�����ֵ���Ƚ�
                            end if;
                        else -- i_EN = '0'
                            s_PwmARR            <= 0;
                            s_PwmCR             <= 0;
                            -- NSL
                            s_PwmFSM <= s_Idle;
                        end if;
                    elsif (s_PwmCNT < s_PwmCR) then
                        o_PWM_CH  <= PWM_CH_Polarity;
                        o_PWM_CHN <= not PWM_CH_Polarity;
                        s_PwmCNT <= s_PwmCNT + 1;
                    elsif (s_PwmCNT <s_PwmARR) then
                        o_PWM_CH  <= not PWM_CH_Polarity;
                        o_PWM_CHN <= PWM_CH_Polarity;
                        s_PwmCNT <= s_PwmCNT + 1;
                    else
                        null;
                    end if;
                when s_Work_OC =>
                    -- SM
                    s_PwmFSM <= s_Work_OC;
                    -- OFL
                    --if (s_PwmCR = 0) then
                    if (i_PwmCompVal = 0) then
                        o_PWM_CH  <= PWM_CH_Idle_State;
                        o_PWM_CHN <= not PWM_CH_Idle_State;
                    elsif (s_PwmCNT = s_PwmCR) then                   
                        if (i_EN = '1') then
                            if (s_PwmParamUpdate = '1') then
                                s_PwmParamUpdate    <= '0';
                                --s_PwmCR             <= s_PwmCNT + i_PwmCompVal;
                                v_PwmCR             := s_PwmCNT + i_PwmCompVal;
                                if (v_PwmCR > c_ValMax) then
                                    s_PwmCR <= v_PwmCR - c_ValMax - 1;
                                else
                                    s_PwmCR <= v_PwmCR;
                                end if;
                            else
--                                s_PwmCR             <= s_PwmCNT + i_PwmCompVal;
                                v_PwmCR             := s_PwmCNT + i_PwmCompVal;
                                if (v_PwmCR > c_ValMax) then
                                    s_PwmCR <= v_PwmCR - c_ValMax - 1;
                                else
                                    s_PwmCR <= v_PwmCR;
                                end if;
                            end if;
                        elsif(i_EN = '0' and s_OC_FSM = s_Two) then -- i_EN = '0'
                            s_PwmFSM            <= s_Idle;
                            s_PwmARR            <= 0;
                            s_PwmCR             <= 0;
                        else
                            null;
                        end if;
                        
                        --s_PwmCNT <= s_PwmCNT + 1;
                        if (s_PwmCNT = c_ValMax) then
                            s_PwmCNT <= 0;
                        else
                            s_PwmCNT <= s_PwmCNT + 1;
                        end if;
                        
                        case s_OC_FSM is
                            when s_One =>
                                o_PWM_CH  <= not PWM_CH_Polarity;
                                o_PWM_CHN <= PWM_CH_Polarity;
                                if (s_PwmCNT = s_PwmCR) then
                                    s_OC_FSM <= s_Two;
                                else
                                    s_OC_FSM <= s_One;
                                end if;
                            when s_Two =>
                                o_PWM_CH  <= PWM_CH_Polarity;
                                o_PWM_CHN <= not PWM_CH_Polarity;
                                if (s_PwmCNT = s_PwmCR) then
                                    s_OC_FSM <= s_One;
                                else
                                    s_OC_FSM <= s_Two;
                                end if;
                            when others=>
                                s_OC_FSM <= s_One;
                        end case;
                    else -- s_PwmCNT /= s_PwmCNT
                        --s_PwmCR  <= s_PwmCR;
                        --s_PwmCNT <= s_PwmCNT + 1;
                        if (s_PwmCNT = c_ValMax) then
                            s_PwmCNT <= 0;
                        else
                            s_PwmCNT <= s_PwmCNT + 1;
                        end if;
                        
                        case s_OC_FSM is
                            when s_One =>
                                o_PWM_CH  <= PWM_CH_Polarity;
                                o_PWM_CHN <= not PWM_CH_Polarity;
                            when s_Two =>
                                o_PWM_CH  <= not PWM_CH_Polarity;
                                o_PWM_CHN <= PWM_CH_Polarity;
                            when others=>
                                s_OC_FSM <= s_One;
                        end case;
                    end if;
                when others =>
                    s_PwmFSM <= s_Idle;
            end case;
        end if;
    end process main_proc;
end Behavioral;
