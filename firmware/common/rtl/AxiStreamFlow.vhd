-------------------------------------------------------------------------------
-- File       : AxiStreamFlow.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2018-02-28
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'SLAC PGP Gen3 Card'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC PGP Gen3 Card', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.SsiPkg.all;

entity AxiStreamFlow is
   port (
      clk             : in  sl;
      rst             : in  sl;
      sAxisMaster     : in  AxiStreamMasterType;
      sAxisCtrl       : out AxiStreamCtrlType;
      mAxisMaster     : out AxiStreamMasterType;
      mAxisCtrl       : in  AxiStreamCtrlType );
end AxiStreamFlow;

architecture mapping of AxiStreamFlow is

   type StateType is (IDLE_S, RECV_S, DUMP_S);
   
   type RegType is record
     state      : StateType;
     axisMaster : AxiStreamMasterType;
   end record;

   constant REG_INIT_C : RegType := (
     state      => IDLE_S,
     axisMaster => AXI_STREAM_MASTER_INIT_C );

   signal r    : RegType := REG_INIT_C;
   signal r_in : RegType;
   
begin

  comb : process ( r, rst, sAxisMaster, mAxisCtrl ) is
    variable v : RegType;
  begin
    v := r;

    v.axisMaster := sAxisMaster;
    
    case r.state is
      when IDLE_S =>
        if sAxisMaster.tValid = '1' then
          if mAxisCtrl.pause = '1' then
            v.axisMaster.tValid := '0';
            if sAxisMaster.tLast = '0' then
              v.state := DUMP_S;
            end if;
          elsif sAxisMaster.tLast = '0' then
            v.state := RECV_S;
          end if;
        end if;
      when RECV_S =>
        if sAxisMaster.tValid = '1' then
          if mAxisCtrl.pause = '1' then
            v.axisMaster := SSI_MASTER_FORCE_EOFE_C;
            if sAxisMaster.tLast = '1' then
              v.state := IDLE_S;
            else
              v.state := DUMP_S;
            end if;
          end if;
        end if;
      when DUMP_S =>
        v.axisMaster.tValid := '0';
        if sAxisMaster.tValid = '1' and sAxisMaster.tLast = '1' then
          v.state := IDLE_S;
        end if;
    end case;

    if rst = '1' then
      v := REG_INIT_C;
    end if;

    r_in <= v;

    sAxisCtrl       <= mAxisCtrl;
    sAxisCtrl.pause <= '0';
    mAxisMaster     <= r.axisMaster;
    
  end process comb;

  seq : process ( clk ) is
  begin
    if rising_edge(clk) then
      r <= r_in;
    end if;
  end process seq;
  
end architecture mapping;
