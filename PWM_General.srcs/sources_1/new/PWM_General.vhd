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
        SYS_CLK_VAL_HZ      :   integer := 50_000_000;  -- 系统主输入时钟值 单位：Hz
        
        WORK_MODE           :   std_logic := '0';   -- 0->PWM 工作模式
                                                     -- 1->OC(输出比较) 工作模式
        
        PWM_CH_Polarity     :   std_logic := '1';   -- PWM输出通道输出时，占空比(首次CNT<CR比较时)-对应关系:
                                                     -- 1->高，0->低
        PWM_CH_Idle_State   :   std_logic := '0'    -- 处于空闲时，通道的电平状态
                                                     -- 1->高，0->低
    );
    Port (
        i_SysClk    :   in      std_logic;  -- 系统时钟
        i_SysNrst   :   in      std_logic;  -- 系统异步复位
        i_EN        :   in      std_logic;  -- 系统控制模块工作位 模块使能：1，禁用：0
        
        i_PwmParamUpdateFlag : in   std_logic;
        i_PwmFreqHz :   in      integer range 0 to 10_000_000; -- 这里设置的是1-100KHz的频率上下限 (计数上限SYS_CLK_VAL_HZ/i_PwmFreqHz)
        i_PwmCompVal:   in      integer range 0 to 50_000_000; -- 这个值与计数值(s_PwmCNT)作比较
        
        o_PWM_CH    :   out     std_logic;  -- PWM 输出通道
        o_PWM_CHN   :   out     std_logic;  -- PWM 输出反向通道
        
        o_CRUIE     :   out     std_logic   -- CNT计数个数达到CR个，产生 CR Update Interrupt Event 脉冲
    );
end PWM_General; 

architecture Behavioral of PWM_General is
    -- 定义常量
    constant c_ValMax   :   integer := 50_000_000;  -- 设定s_PwmCR和s_PwmCNT的最大
    -- 定义信号变量
    signal  s_PwmParamUpdateFlagSync : std_logic := '0'; --i_PwmParamUpdateFlag的同步信号
    signal  s_PwmParamUpdate :   std_logic := '0';            -- 0 ->参数不会生效，使用原参数输出或者无输出(首次运行)；
                                                               -- 1 ->参数起作用，如i_EN=1,PWM输出
    signal  s_PwmARR    :   integer range 0 to 50_000_000 := 0; -- PWM自动重装载值，由主时钟和PWM频率决定，控制PWM频率(对主时钟计数次数)
    signal  s_PwmCR     :   integer range 0 to 50_000_000 := 0; -- PWM比较寄存器，即基准线
    signal  s_PwmCNT    :   integer range 0 to 50_000_000 := 0; -- PWM计数器，与s_PwmCR比较处理翻转，s_PwmARR决定计数范围
    
    type    t_FSM   is  (s_Idle, s_Work_PWM, s_Work_OC);
    signal  s_PwmFSM   :   t_FSM   :=  s_Idle;

    type    t_OC_FSM is (s_One, s_Two);
    signal  s_OC_FSM   :   t_OC_FSM:=  s_One;

begin
    -- 组合逻辑
    o_CRUIE <=  '0' when (i_PwmCompVal = 0 or s_PwmARR = 0 or s_PwmCR = s_PwmARR+1) and WORK_MODE = '0' and i_EN = '1' else
                '1' when s_PwmCNT = s_PwmCR and i_EN = '1' and WORK_MODE = '0' else
                '0' when i_PwmCompVal  = 0 and WORK_MODE = '1' and i_EN = '1' else
                '1' when (s_PwmCNT = s_PwmCR - 1 or s_PwmCNT = s_PwmCR + c_ValMax) and i_EN = '1' and WORK_MODE = '1' else
                '0';

    -- 顺序逻辑
    main_proc: process (i_SysClk, i_SysNrst)
    -- 定义变量
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
            -- 参数更新信号生成和参数信息锁定
            s_PwmParamUpdateFlagSync <= i_PwmParamUpdateFlag;
            if (i_PwmParamUpdateFlag = '0' and s_PwmParamUpdateFlagSync = '1' and s_PwmParamUpdate = '0' and i_EN = '1') then
                s_PwmParamUpdate    <= '1';
            else
                null;
            end if;
            
            -- 主状态机，处理过程
            case s_PwmFSM is
                when s_Idle =>        -- 空闲状态，等待参数设置(即启动信号)
                    -- OFL
                    o_PWM_CH     <= PWM_CH_Idle_State;
                    o_PWM_CHN    <= not PWM_CH_Idle_State;

                    if (s_PwmParamUpdate = '1' and i_EN = '1') then
                        -- OFL
                        s_PwmParamUpdate    <= '0';
                        s_PwmARR            <= SYS_CLK_VAL_HZ / i_PwmFreqHz - 1; -- cnt最大计数值
                        s_PwmCR             <= i_PwmCompVal;   -- cnt与这个值作比较
                        -- NSL
                        if (WORK_MODE = '0') then
                            s_PwmFSM <= s_Work_PWM; -- 进入PWM工作模式，CNT计数到ARR，CR控制占空比
                        else
                            s_PwmFSM <= s_Work_OC;  -- 进入输出比较模式 CNT与CR比较，翻转
                            s_OC_FSM <= s_One;
                        end if;
                    elsif (i_EN = '0') then
                        s_PwmARR            <= 0;
                        s_PwmCR             <= 0;
                    else
                        s_PwmARR            <= s_PwmARR;
                        s_PwmCR             <= s_PwmCR;
                    end if;
                when s_Work_PWM =>        -- 按照设定参数输出PWM波 (由输入的pwm频率和占空比参数CR决定)
                    -- SM
                    s_PwmFSM <= s_Work_PWM;
                
                    if (s_PwmCNT = s_PwmARR) then
                        -- CNT清零
                        s_PwmCNT <= 0;
                        if (s_PwmCR = s_PwmARR+1) then
                            o_PWM_CH  <= PWM_CH_Polarity;
                            o_PWM_CHN <= not PWM_CH_Polarity;
                        else
                            o_PWM_CH  <= not PWM_CH_Polarity;
                            o_PWM_CHN <= PWM_CH_Polarity;
                        end if;

                        -- 参数更新标志有效
                        if (i_EN = '1') then
                            if (s_PwmParamUpdate = '1') then
                                s_PwmParamUpdate    <= '0';
                                s_PwmARR            <= SYS_CLK_VAL_HZ / i_PwmFreqHz - 1; -- cnt最大计数值
                                s_PwmCR             <= i_PwmCompVal;   -- cnt与这个值作比较
                            else
                                s_PwmARR            <= s_PwmARR; -- cnt最大计数值
                                s_PwmCR             <= s_PwmCR;  -- cnt与这个值作比较
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
