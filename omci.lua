--[[ 
   Wireshark dissector for ITU-T G984.4 and G988 OMCI frames.
   Copyright (C) 2012 Technicolor 
   Authors:
   Dirk Van Aken (dirk.vanaken@technicolor.com),
   Olivier Hardouin (olivier.hardouin@technicolor.com)

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; version 2
   of the License.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 
   Description:
   Wireshark dissector for ONT Management and Control Interface (OMCI) protocol (ITU-T G984.4, ITU-T G988)
   This protocol is used on Gigabit Passive Optical Network (GPON) between Optical Line Termition (OLT, the network side) and Optical Network Termination (ONT, the end user side) units.
   This is management protocol used to configure services (like Ethernet, QoS, Video overlay, Tx/Rx control) on the ONT.
   The dissector applies on UDP or Ethernet packet that contains a copy of OMCI data going between ONT and OLT as explained in appendix III of ITU-T G988
  
   Links that were used to create this dissector:
   General presentation about WS dissector in Lua: http://sharkfest.wireshark.org/sharkfest.09/DT06_Bjorlykke_Lua%20Scripting%20in%20Wireshark.pdf
   Standard Wireshark dissector: http://www.wireshark.org/docs/wsug_html_chunked/wslua_dissector_example.html
   Lua Support in Wireshark: http://www.wireshark.org/docs/wsug_html_chunked/wsluarm.html
   Nice Wireshark dissector example: http://thomasfischer.biz/?p=175
   Another nice Wireshark dissector example: http://code.google.com/p/eathena/source/browse/devel/FlavioJS/athena.lua?r=9341
  
   The dissector binary to hexadecimal conversion, module available at http://www.dialectronics.com/Lua/code/BinDecHex.shtml
  
   Note from the author:
   *) Not all ME classes described in the OMCI standards are supported in this dissector (any support to complete the list is very welcome)
   *) This implementation is the first LUA SW written by the author. It (certainly) could be more efficient (any comment is welcome) 

--]]

require "BinDecHex"

-- Create a new dissector
omciproto = Proto ("omci", "OMCI Protocol")

-- init function
function omciproto.init()
end

local msgtype_meta = {
  __index = function(t, k)   
    if k < 4 or k > 29 then
      return "Reserved"
    end
  end
}

local msgtype = {
	[4]="Create",
	[5]="Create Complete Connection",
	[6]="Delete",
	[7]="Delete Complete Connection",
	[8]="Set",
	[9]="Get",
	[10]="Get Complete Connection",
	[11]="Get All Alarms",
	[12]="Get All Alarms Next",
	[13]="MIB Upload",
	[14]="MIB Upload Next",
	[15]="MIB Reset",
	[16]="Alarm",
	[17]="Attribute Value Change",
	[18]="Test",
	[19]="Start Software Download",
	[20]="Download Section",
	[21]="End Software Download",
	[22]="Activate Software",
	[23]="Commit Software",
	[24]="Synchronize Time",
	[25]="Reboot",
	[26]="Get Next",
	[27]="Test Result",
	[28]="Get Current Data",
	[29]="Set Table"
}
setmetatable(msgtype, msgtype_meta)

local msg_result_meta = {
  __index = function(t, k)   
    if k == 8 or k > 9 then
      return "Unknown"
    end
  end
}

local msg_result= {
	[0] = "Command processed successfully",
	[1] = "Command processing error",
	[2] = "Command not supported",
	[3] = "Command parameter error",
	[4] = "Unknown managed entity",
	[5] = "Unknown managed entity instance",
	[6] = "Device busy",
	[7] = "Instance exists",
	[9] = "Attribute failed or unknown"
}
setmetatable(msg_result, msg_result_meta)

local test_message_name = {}
local test_message_name_meta = {
	__index = function(t, k)
		if k >= 0 and k <= 6 then
			return "Reserved for future use"
		elseif k == 7 then
			return "Self test"
		elseif k > 7 and k <=255 then 
			return "Vendor specific" 
		else
			return "***ERROR: Not a Test ID*** (" .. k .. ")"
		end
	end
}
setmetatable(test_message_name, test_message_name_meta)

local mt2 = {
  __index = function(t2, k)   
	local returntable = {}
	if k == 1 then
		returntable.me_class_name= "ONTB-PON"
	elseif k ==   2	then
		returntable.me_class_name= "ONU data"
	elseif k ==   3	then
		returntable.me_class_name= "PON IF line cardholder"
	elseif k ==   4	then
		returntable.me_class_name= "PON IF line card"
	elseif k ==   5	then
		returntable.me_class_name = "Cardholder"
	elseif k ==   6	then
		returntable.me_class_name = "Circuit pack"
	elseif k ==   7	then
		returntable.me_class_name = "Software image"
	elseif k ==   8	then
		returntable.me_class_name = "UNIB-PON"
	elseif k ==   9	then
		returntable.me_class_name = "TC AdapterB-PON"
	elseif k ==  10	then
		returntable.me_class_name = "Physical path termination point ATM UNI"
	elseif k ==  11	then
		returntable.me_class_name = "Physical path termination point Ethernet UNI"
	elseif k ==  12	then
		returntable.me_class_name = "Physical path termination point CES UNI"
	elseif k ==  13	then
		returntable.me_class_name = "Logical N  64 kbit/s sub-port connection termination point"
	elseif k ==  14	then
		returntable.me_class_name = "Interworking VCC termination point"
	elseif k ==  15	then
		returntable.me_class_name = "AAL1 profileB-PON"
	elseif k ==  16	then
		returntable.me_class_name = "AAL5 profile"
	elseif k ==  17	then
		returntable.me_class_name = "AAL1 protocol monitoring history dataB-PON"
	elseif k ==  18	then
		returntable.me_class_name = "AAL5 performance monitoring history data"
	elseif k ==  19	then
		returntable.me_class_name = "AAL2 profile"
	elseif k ==  20	then
		returntable.me_class_name = "Intentionally left blank)"
	elseif k ==  21	then
		returntable.me_class_name = "CES service profile"
	elseif k ==  22	then
		returntable.me_class_name = "Reserved)"
	elseif k ==  23	then
		returntable.me_class_name = "CES physical interface performance monitoring history data"
	elseif k ==  24	then
		returntable.me_class_name = "Ethernet performance monitoring history data"
	elseif k ==  25	then
		returntable.me_class_name = "VP network CTPBPON"
	elseif k ==  26	then
		returntable.me_class_name = "ATM VP cross-connection"
	elseif k ==  27	then
		returntable.me_class_name = "Priority queueB-PON"
	elseif k ==  28	then
		returntable.me_class_name = "DBR/CBR traffic descriptor"
	elseif k ==  29	then
		returntable.me_class_name = "UBR traffic descriptor"
	elseif k ==  30	then
		returntable.me_class_name = "SBR1/VBR1 traffic descriptor"
	elseif k ==  31	then
		returntable.me_class_name = "SBR2/VBR2 traffic descriptor"
	elseif k ==  32	then
		returntable.me_class_name = "SBR3/VBR3 traffic descriptor"
	elseif k ==  33	then
		returntable.me_class_name = "ABR traffic descriptor"
	elseif k ==  34	then
		returntable.me_class_name = "GFR traffic descriptor"
	elseif k ==  35	then
		returntable.me_class_name = "ABT/DT/IT traffic descriptor"
	elseif k ==  36	then
		returntable.me_class_name = "UPC disagreement monitoring history dataB-PON"
	elseif k ==  37	then
		returntable.me_class_name = "Intentionally left blank)"
	elseif k ==  38	then
		returntable.me_class_name = "ANI (B-PON)"
	elseif k ==  39	then
		returntable.me_class_name = "PON TC adapter"
	elseif k ==  40	then
		returntable.me_class_name = "PON physical path termination point"
	elseif k ==  41	then
		returntable.me_class_name = "TC adapter protocol monitoring history data"
	elseif k ==  42	then
		returntable.me_class_name = "Threshold dataB-PON"
	elseif k ==  43	then
		returntable.me_class_name = "Operator specific"
	elseif k ==  44	then
		returntable.me_class_name = "Vendor specific"
	elseif k ==  45	then
		returntable.me_class_name = "MAC bridge service profile"
	elseif k ==  46	then
		returntable.me_class_name = "MAC bridge configuration data"
	elseif k ==  47	then
		returntable.me_class_name = "MAC bridge port configuration data"
	elseif k ==  48	then
		returntable.me_class_name = "MAC bridge port designation data"
	elseif k ==  49	then
		returntable.me_class_name = "MAC bridge port filter table data"
	elseif k ==  50	then
		returntable.me_class_name = "MAC bridge port bridge table data"
	elseif k ==  51	then
		returntable.me_class_name = "MAC bridge performance monitoring history data"
	elseif k ==  52	then
		returntable.me_class_name = "MAC bridge port performance monitoring history data"
	elseif k ==  53	then
		returntable.me_class_name = "Physical path termination point POTS UNI"
	elseif k ==  54	then
		returntable.me_class_name = "Voice CTP"
	elseif k ==  55	then
		returntable.me_class_name = "Voice PM history data"
	elseif k ==  56	then
		returntable.me_class_name = "AAL2 PVC profileB-PON"
	elseif k ==  57	then
		returntable.me_class_name = "AAL2 CPS protocol monitoring history dataB-PON"
	elseif k ==  58	then
		returntable.me_class_name = "Voice service profile"
	elseif k ==  59	then
		returntable.me_class_name = "LES service profile"
	elseif k ==  60	then
		returntable.me_class_name = "AAL2 SSCS parameter profile1"
	elseif k ==  61	then
		returntable.me_class_name = "AAL2 SSCS parameter profile2"
	elseif k ==  62	then
		returntable.me_class_name = "VP performance monitoring history data"
	elseif k ==  63	then
		returntable.me_class_name = "Traffic schedulerB-PON"
	elseif k ==  64	then
		returntable.me_class_name = "T-CONT buffer"
	elseif k ==  65	then
		returntable.me_class_name = "UBR+ traffic descriptor"
	elseif k ==  66	then
		returntable.me_class_name = "AAL2 SSCS protocol monitoring history dataB-PON"
	elseif k ==  67	then
		returntable.me_class_name = "IP port configuration data"
	elseif k ==  68	then
		returntable.me_class_name = "IP router service profile"
	elseif k ==  69	then
		returntable.me_class_name = "IP router configuration data"
	elseif k ==  70	then
		returntable.me_class_name = "IP router performance monitoring history data 1"
	elseif k ==  71	then
		returntable.me_class_name = "IP router performance monitoring history data 2"
	elseif k ==  72	then
		returntable.me_class_name = "ICMP performance monitoring history data 1"
	elseif k ==  73	then
		returntable.me_class_name = "ICMP performance monitoring history data 2"
	elseif k ==  74	then
		returntable.me_class_name = "IP route table"
	elseif k ==  75	then
		returntable.me_class_name = "IP static routes"
	elseif k ==  76	then
		returntable.me_class_name = "ARP service profile"
	elseif k ==  77	then
		returntable.me_class_name = "ARP configuration data"
	elseif k ==  78	then
		returntable.me_class_name = "VLAN tagging operation configuration data"
	elseif k ==  79	then
		returntable.me_class_name = "MAC bridge port filter pre-assign table"
	elseif k ==  80	then
		returntable.me_class_name = "Physical path termination point ISDN UNI"
	elseif k ==  81	then
		returntable.me_class_name = "(Reserved)"
	elseif k ==  82	then
		returntable.me_class_name = "Physical path termination point video UNI"
	elseif k ==  83	then
		returntable.me_class_name = "Physical path termination point LCT UNI"
	elseif k ==  84	then
		returntable.me_class_name = "VLAN tagging filter data"
	elseif k ==  85	then
		returntable.me_class_name = "ONUB-PON"
	elseif k ==  86	then
		returntable.me_class_name = "ATM VC cross-connection"
	elseif k ==  87	then
		returntable.me_class_name = "VC network CTPB-PON"
	elseif k ==  88	then
		returntable.me_class_name = "VC PM history data"
	elseif k ==  89	then
		returntable.me_class_name = "Ethernet performance monitoring history data 2"
	elseif k ==  90	then
		returntable.me_class_name = "Physical path termination point video ANI"
	elseif k ==  91	then
		returntable.me_class_name = "Physical path termination point IEEE 802.11 UNI"
	elseif k ==  92	then
		returntable.me_class_name = "IEEE 802.11 station management data 1"
	elseif k ==  93	then
		returntable.me_class_name = "IEEE 802.11 station management data 2"
	elseif k ==  94	then
		returntable.me_class_name = "IEEE 802.11 general purpose object"
	elseif k ==  95	then
		returntable.me_class_name = "IEEE 802.11 MAC and PHY operation and antenna data"
	elseif k ==  96	then
		returntable.me_class_name = "IEEE 802.11 performance monitoring history data"
	elseif k ==  97	then
		returntable.me_class_name = "IEEE 802.11 PHY FHSS DSSS IR tables"
	elseif k ==  98	then
		returntable.me_class_name = "Physical path termination point xDSL UNI part 1"
	elseif k ==  99	then
		returntable.me_class_name = "Physical path termination point xDSL UNI part 2"
	elseif k == 100	then
		returntable.me_class_name = "xDSL line inventory and status data part 1"
	elseif k == 101	then
		returntable.me_class_name = "xDSL line inventory and status data part 2"
	elseif k == 102	then
		returntable.me_class_name = "xDSL channel downstream status data"
	elseif k == 103	then
		returntable.me_class_name = "xDSL channel upstream status data"
	elseif k == 104	then
		returntable.me_class_name = "xDSL line configuration profile part 1"
	elseif k == 105	then
		returntable.me_class_name = "xDSL line configuration profile part 2"
	elseif k == 106	then
		returntable.me_class_name = "xDSL line configuration profile part 3"
	elseif k == 107	then
		returntable.me_class_name = "xDSL channel configuration profile"
	elseif k == 108	then
		returntable.me_class_name = "xDSL subcarrier masking downstream profile"
	elseif k == 109	then
		returntable.me_class_name = "xDSL subcarrier masking upstream profile"
	elseif k == 110	then
		returntable.me_class_name = "xDSL PSD mask profile"
	elseif k == 111	then
		returntable.me_class_name = "xDSL downstream RFI bands profile"
	elseif k == 112	then
		returntable.me_class_name = "xDSL xTU-C performance monitoring history data part 1"
	elseif k == 113	then
		returntable.me_class_name = "xDSL xTU-R performance monitoring history data"
	elseif k == 114	then
		returntable.me_class_name = "xDSL xTU-C channel performance monitoring history data"
	elseif k == 115	then
		returntable.me_class_name = "xDSL xTU-R channel performance monitoring history data"
	elseif k == 116	then
		returntable.me_class_name = "TC adaptor performance monitoring history data xDSL"
	elseif k == 117	then
		returntable.me_class_name = "Physical path termination point VDSL UNI (ITU-T G.993.1 VDSL1)"
	elseif k == 118	then
		returntable.me_class_name = "VDSL VTU-O physical data"
	elseif k == 119	then
		returntable.me_class_name = "VDSL VTU-R physical data"
	elseif k == 120	then
		returntable.me_class_name = "VDSL channel data"
	elseif k == 121	then
		returntable.me_class_name = "VDSL line configuration profile"
	elseif k == 122	then
		returntable.me_class_name = "VDSL channel configuration profile"
	elseif k == 123	then
		returntable.me_class_name = "VDSL band plan configuration profile"
	elseif k == 124	then
		returntable.me_class_name = "VDSL VTU-O physical interface monitoring history data"
	elseif k == 125	then
		returntable.me_class_name = "VDSL VTU-R physical interface monitoring history data"
	elseif k == 126	then
		returntable.me_class_name = "VDSL VTU-O channel performance monitoring history data"
	elseif k == 127	then
		returntable.me_class_name = "VDSL VTU-R channel performance monitoring history data"
	elseif k == 128	then
		returntable.me_class_name = "Video return path service profile"
	elseif k == 129	then
		returntable.me_class_name = "Video return path performance monitoring history data"
	elseif k == 130	then
		returntable.me_class_name = "IEEE 802.1p mapper service profile"
	elseif k == 131	then
		returntable.me_class_name = "OLT-G"
	elseif k == 132	then
		returntable.me_class_name = "Multicast interworking VCC termination point"
	elseif k == 133	then
		returntable.me_class_name = "ONU power shedding"
	elseif k == 134	then
		returntable.me_class_name = "IP host config data"
	elseif k == 135	then
		returntable.me_class_name = "IP host performance monitoring history data"
	elseif k == 136	then
		returntable.me_class_name = "TCP/UDP config data"
	elseif k == 137	then
		returntable.me_class_name = "Network address"
	elseif k == 138	then
		returntable.me_class_name = "VoIP config data"
	elseif k == 139	then
		returntable.me_class_name = "VoIP voice CTP"
	elseif k == 140	then
		returntable.me_class_name = "Call control performance monitoring history data"
	elseif k == 141	then
		returntable.me_class_name = "VoIP line status"
	elseif k == 142	then
		returntable.me_class_name = "VoIP media profile"
	elseif k == 143	then
		returntable.me_class_name = "RTP profile data"
	elseif k == 144	then
		returntable.me_class_name = "RTP performance monitoring history data"
	elseif k == 145	then
		returntable.me_class_name = "Network dial plan table"
	elseif k == 146	then
		returntable.me_class_name = "VoIP application service profile"
	elseif k == 147	then
		returntable.me_class_name = "VoIP feature access codes"
	elseif k == 148	then
		returntable.me_class_name = "Authentication security method"
	elseif k == 149	then
		returntable.me_class_name = "SIP config portal"
	elseif k == 150	then
		returntable.me_class_name = "SIP agent config data"
	elseif k == 151	then
		returntable.me_class_name = "SIP agent performance monitoring history data"
	elseif k == 152	then
		returntable.me_class_name = "SIP call initiation performance monitoring history data"
	elseif k == 153	then
		returntable.me_class_name = "SIP user data"
	elseif k == 154	then
		returntable.me_class_name = "MGC config portal"
	elseif k == 155	then
		returntable.me_class_name = "MGC config data"
	elseif k == 156	then
		returntable.me_class_name = "MGC performance monitoring history data"
	elseif k == 157	then
		returntable.me_class_name = "Large string"
	elseif k == 158	then
		returntable.me_class_name = "ONU remote debug"
	elseif k == 159	then
		returntable.me_class_name = "Equipment protection profile"
	elseif k == 160	then
		returntable.me_class_name = "Equipment extension package"
	elseif k == 161	then
		returntable.me_class_name = "Port-mapping packageBPON (B-PON only; use 297 for G-PON)"
	elseif k == 162	then
		returntable.me_class_name = "Physical path termination point MoCA UNI"
	elseif k == 163	then
		returntable.me_class_name = "MoCA Ethernet performance monitoring history data"
	elseif k == 164	then
		returntable.me_class_name = "MoCA interface performance monitoring history data"
	elseif k == 165	then
		returntable.me_class_name = "VDSL2 line configuration extensions"
	elseif k == 166	then
		returntable.me_class_name = "xDSL line inventory and status data part 3"
	elseif k == 167	then
		returntable.me_class_name = "xDSL line inventory and status data part 4"
	elseif k == 168	then
		returntable.me_class_name = "VDSL2 line inventory and status data part 1"
	elseif k == 169	then
		returntable.me_class_name = "VDSL2 line inventory and status data part 2"
	elseif k == 170	then
		returntable.me_class_name = "VDSL2 line inventory and status data part 3"
	elseif k == 171	then
		returntable.me_class_name = "Extended VLAN tagging operation configuration data"
	elseif k >= 172	and k <= 239 then
		returntable.me_class_name = "239 Reserved for future B-PON managed entities"
	elseif k >= 240 and k <= 255 then
		returntable.me_class_name = "Reserved for vendor-specific managed entities"
	elseif k == 256	then
		returntable.me_class_name = "ONU-G (NOTE – In [ITU-T G.984.4] this was called ONT-G)"
	elseif k == 257	then
		returntable.me_class_name = "ONU2-G (NOTE – In [ITU-T G.984.4] this was called ONT2-G)"
	elseif k == 258	then
		returntable.me_class_name = "ONU-G (deprecated – note that the name is re-used for code point 256)"
	elseif k == 259	then
		returntable.me_class_name = "ONU2-G (deprecated – note that the name is re-used for code point 257)"
	elseif k == 260	then
		returntable.me_class_name = "PON IF line card-G"
	elseif k == 261	then
		returntable.me_class_name = "PON TC adapter-G"
	elseif k == 262	then
		returntable.me_class_name = "T-CONT"
	elseif k == 263	then
		returntable.me_class_name = "ANI-G"
	elseif k == 264	then
		returntable.me_class_name = "UNI-G"
	elseif k == 265	then
		returntable.me_class_name = "ATM interworking VCC termination point"
	elseif k == 266	then
		returntable.me_class_name = "GEM interworking termination point"
	elseif k == 267	then
		returntable.me_class_name = "GEM port performance monitoring history data (obsolete)"
	elseif k == 268	then
		returntable.me_class_name = "GEM port network CTP"
	elseif k == 269	then
		returntable.me_class_name = "VP network CTP"
	elseif k == 270	then
		returntable.me_class_name = "VC network CTP-G"
	elseif k == 271	then
		returntable.me_class_name = "GAL TDM profile (deprecated)"
	elseif k == 272	then
		returntable.me_class_name = "GAL Ethernet profile"
	elseif k == 273	then
		returntable.me_class_name = "Threshold data 1"
	elseif k == 274	then
		returntable.me_class_name = "Threshold data 2"
	elseif k == 275	then
		returntable.me_class_name = "GAL TDM performance monitoring history data (deprecated)"
	elseif k == 276	then
		returntable.me_class_name = "GAL Ethernet performance monitoring history data"
	elseif k == 277	then
		returntable.me_class_name = "Priority queue"
	elseif k == 278	then
		returntable.me_class_name = "Traffic scheduler"
	elseif k == 279	then
		returntable.me_class_name = "Protection data"
	elseif k == 280	then
		returntable.me_class_name = "Traffic descriptor"
	elseif k == 281	then
		returntable.me_class_name = "Multicast GEM interworking termination point"
	elseif k == 282	then
		returntable.me_class_name = "Pseudowire termination point"
	elseif k == 283	then
		returntable.me_class_name = "RTP pseudowire parameters"
	elseif k == 284	then
		returntable.me_class_name = "Pseudowire maintenance profile"
	elseif k == 285	then
		returntable.me_class_name = "Pseudowire performance monitoring history data"
	elseif k == 286	then
		returntable.me_class_name = "Ethernet flow termination point"
	elseif k == 287	then
		returntable.me_class_name = "OMCI"
	elseif k == 288	then
		returntable.me_class_name = "Managed entity"
	elseif k == 289	then
		returntable.me_class_name = "Attribute"
	elseif k == 290	then
		returntable.me_class_name = "Dot1X port extension package"
	elseif k == 291	then
		returntable.me_class_name = "Dot1X configuration profile"
	elseif k == 292	then
		returntable.me_class_name = "Dot1X performance monitoring history data"
	elseif k == 293	then
		returntable.me_class_name = "Radius performance monitoring history data"
	elseif k == 294	then
		returntable.me_class_name = "TU CTP"
	elseif k == 295	then
		returntable.me_class_name = "TU performance monitoring history data"
	elseif k == 296	then
		returntable.me_class_name = "Ethernet performance monitoring history data 3"
	elseif k == 297	then
		returntable.me_class_name = "Port-mapping package"
	elseif k == 298	then
		returntable.me_class_name = "Dot1 rate limiter"
	elseif k == 299	then
		returntable.me_class_name = "Dot1ag maintenance domain"
	elseif k == 300	then
		returntable.me_class_name = "Dot1ag maintenance association"
	elseif k == 301	then
		returntable.me_class_name = "Dot1ag default MD level"
	elseif k == 302	then
		returntable.me_class_name = "Dot1ag MEP"
	elseif k == 303	then
		returntable.me_class_name = "Dot1ag MEP status"
	elseif k == 304	then
		returntable.me_class_name = "Dot1ag MEP CCM database"
	elseif k == 305	then
		returntable.me_class_name = "Dot1ag CFM stack"
	elseif k == 306	then
		returntable.me_class_name = "Dot1ag chassis-management info"
	elseif k == 307	then
		returntable.me_class_name = "Octet string"
	elseif k == 308	then
		returntable.me_class_name = "General purpose buffer"
	elseif k == 309	then
		returntable.me_class_name = "Multicast operations profile"
	elseif k == 310	then
		returntable.me_class_name = "Multicast subscriber config info"
	elseif k == 311	then
		returntable.me_class_name = "Multicast subscriber monitor"
	elseif k == 312	then
		returntable.me_class_name = "FEC performance monitoring history data"
	elseif k == 313	then
		returntable.me_class_name = "RE ANI-G"
	elseif k == 314	then
		returntable.me_class_name = "Physical path termination point RE UNI"
	elseif k == 315	then
		returntable.me_class_name = "RE upstream amplifier"
	elseif k == 316	then
		returntable.me_class_name = "RE downstream amplifier"
	elseif k == 317	then
		returntable.me_class_name = "RE config portal"
	elseif k == 318	then
		returntable.me_class_name = "File transfer controller"
	elseif k == 319	then
		returntable.me_class_name = "CES physical interface performance monitoring history data 2"
	elseif k == 320	then
		returntable.me_class_name = "CES physical interface performance monitoring history data 3"
	elseif k == 321	then
		returntable.me_class_name = "Ethernet frame performance monitoring history data downstream"
	elseif k == 322	then
		returntable.me_class_name = "Ethernet frame performance monitoring history data upstream"
	elseif k == 323	then
		returntable.me_class_name = "VDSL2 line configuration extensions 2"
	elseif k == 324	then
		returntable.me_class_name = "xDSL impulse noise monitor performance monitoring history data"
	elseif k == 325	then
		returntable.me_class_name = "xDSL line inventory and status data part 5"
	elseif k == 326	then
		returntable.me_class_name = "xDSL line inventory and status data part 6"
	elseif k == 327	then
		returntable.me_class_name = "xDSL line inventory and status data part 7"
	elseif k == 328	then
		returntable.me_class_name = "RE common amplifier parameters"
	elseif k == 329	then
		returntable.me_class_name = "Virtual Ethernet interface point"
	elseif k == 330	then
		returntable.me_class_name = "Generic status portal"
	elseif k == 331	then
		returntable.me_class_name = "ONU-E"
	elseif k == 332	then
		returntable.me_class_name = "Enhanced security control"
	elseif k == 333	then
		returntable.me_class_name = "MPLS pseudowire termination point"
	elseif k == 334	then
		returntable.me_class_name = "Ethernet frame extended PM"
	elseif k == 335	then
		returntable.me_class_name = "SNMP configuration data"
	elseif k == 336	then
		returntable.me_class_name = "ONU dynamic power management control"
	elseif k == 337	then
		returntable.me_class_name = "PW ATM configuration data"
	elseif k == 338	then
		returntable.me_class_name = "PW ATM performance monitoring history data"
	elseif k == 339	then
		returntable.me_class_name = "PW Ethernet configuration data"
	elseif k == 340	then
		returntable.me_class_name = "BBF TR-069 management server"
	elseif k == 341	then
		returntable.me_class_name = "GEM port network CTP performance monitoring history data"
	elseif k == 342	then
		returntable.me_class_name = "TCP/UDP performance monitoring history data"
	elseif k == 343	then
		returntable.me_class_name = "Energy consumption performance monitoring history data"
	elseif k == 344	then
		returntable.me_class_name = "XG-PON TC performance monitoring history data"
	elseif k == 345	then
		returntable.me_class_name = "XG-PON downstream management performance monitoring history data"
	elseif k == 346	then
		returntable.me_class_name = "XG-PON upstream management performance monitoring history data"
	elseif k == 347	then
		returntable.me_class_name = "IPv6 host config data"
	elseif k == 348	then
		returntable.me_class_name = "MAC bridge port ICMPv6 process pre-assign table"
	elseif k == 349	then
		returntable.me_class_name = "PoE control"
	elseif k >= 350 and k <= 399 then
		returntable.me_class_name = "Reserved for vendor-specific use"
	elseif k == 400	then
		returntable.me_class_name = "Ethernet pseudowire parameters"
	elseif k == 401	then
		returntable.me_class_name = "Physical path termination point RS232/RS485 UNI"
	elseif k == 402	then
		returntable.me_class_name = "RS232/RS485 port operation configuration data"
	elseif k == 403	then
		returntable.me_class_name = "RS232/RS485 performance monitoring history data"
	elseif k == 404	then
		returntable.me_class_name = "L2 multicast GEM interworking termination point"
	elseif k == 405	then
		returntable.me_class_name = "ANI-E"
	elseif k == 406	then
		returntable.me_class_name = "EPON downstream performance monitoring configuration"
	elseif k == 407	then
		returntable.me_class_name = "SIP agent config data 2"
	elseif k == 408	then
		returntable.me_class_name = "xDSL xTU-C performance monitoring history data part 2"
	elseif k == 409	then
		returntable.me_class_name = "PTM performance monitoring history data xDSL"
	elseif k == 410	then
		returntable.me_class_name = "VDSL2 line configuration extensions 3"
	elseif k == 411	then
		returntable.me_class_name = "Vectoring line configuration extensions"
	elseif k == 412	then
		returntable.me_class_name = "xDSL channel configuration profile part 2"
	elseif k == 413	then
		returntable.me_class_name = "xTU data gathering configuration"
	elseif k == 414	then
		returntable.me_class_name = "xDSL line inventory and status data part 8"
	elseif k == 415	then
		returntable.me_class_name = "VDSL2 line inventory and status data part 4"
	elseif k == 416	then
		returntable.me_class_name = "Vectoring line inventory and status data"
	elseif k == 417	then
		returntable.me_class_name = "Data gathering line test, diagnostic and status"
	elseif k == 418	then
		returntable.me_class_name = "EFM bonding group"
	elseif k == 419	then
		returntable.me_class_name = "EFM bonding link"
	elseif k == 420	then
		returntable.me_class_name = "EFM bonding group performance monitoring history data"
	elseif k == 421	then
		returntable.me_class_name = "EFM bonding group performance monitoring history data part 2"
	elseif k == 422	then
		returntable.me_class_name = "EFM bonding link performance monitoring history data"
	elseif k == 423	then
		returntable.me_class_name = "EFM bonding port performance monitoring history data"
	elseif k == 424	then
		returntable.me_class_name = "EFM bonding port performance monitoring history data part 2"
	elseif k == 425	then
		returntable.me_class_name = "Ethernet frame extended PM 64 bit"
	elseif k == 426	then
		returntable.me_class_name = "Threshold data 64 bit"
	elseif k == 427	then
		returntable.me_class_name = "Physical path termination point UNI part 3 (FAST)"
	elseif k == 428	then
		returntable.me_class_name = "FAST line configuration profile part 1"
	elseif k == 429	then
		returntable.me_class_name = "FAST line configuration profile part 2"
	elseif k == 430	then
		returntable.me_class_name = "FAST line configuration profile part 3"
	elseif k == 431	then
		returntable.me_class_name = "FAST line configuration profile part 4"
	elseif k == 432	then
		returntable.me_class_name = "FAST channel configuration profile, part 1"
	elseif k == 433	then
		returntable.me_class_name = "FAST data path configuration profile"
	elseif k == 434	then
		returntable.me_class_name = "FAST vectoring line configuration extensions"
	elseif k == 435	then
		returntable.me_class_name = "FAST line inventory and status data"
	elseif k == 436	then
		returntable.me_class_name = "FAST line inventory and status data part 2"
	elseif k == 437	then
		returntable.me_class_name = "FAST xTU-C performance monitoring history data"
	elseif k == 438	then
		returntable.me_class_name = "FAST xTU-R performance monitoring history data"
	elseif k == 439	then
		returntable.me_class_name = "OpenFlow config data"
	elseif k == 440	then
		returntable.me_class_name = "Time Status Message"
	elseif k == 441	then
		returntable.me_class_name = "ONU3-G"
	elseif k == 442	then
		returntable.me_class_name = "TWDM System Profile managed entity"
	elseif k == 443	then
		returntable.me_class_name = "TWDM channel managed entity"
	elseif k == 444	then
		returntable.me_class_name = "TWDM channel PHY/LODS performance monitoring history data"
	elseif k == 445	then
		returntable.me_class_name = "TWDM channel XGEM performance monitoring history data"
	elseif k == 446	then
		returntable.me_class_name = "TWDM channel PLOAM performance monitoring history data part 1"
	elseif k == 447	then
		returntable.me_class_name = "TWDM channel PLOAM performance monitoring history data part 2"
	elseif k == 448	then
		returntable.me_class_name = "TWDM channel PLOAM performance monitoring history data part 3"
	elseif k == 449	then
		returntable.me_class_name = "TWDM channel tuning performance monitoring history data part 1"
	elseif k == 450	then
		returntable.me_class_name = "TWDM channel tuning performance monitoring history data part 2"
	elseif k == 451	then
		returntable.me_class_name = "TWDM channel tuning performance monitoring history data part 3"
	elseif k == 452	then
		returntable.me_class_name = "TWDM channel OMCI performance monitoring history data"
	elseif k == 453	then
		returntable.me_class_name = "Enhanced FEC performance monitoring history data"
	elseif k == 454	then
		returntable.me_class_name = "Enhanced TC performance monitoring history data"
	elseif k == 455	then
		returntable.me_class_name = "Link aggregation service profile"
	elseif k == 456	then
		returntable.me_class_name = "ONU manufacturing data"
	elseif k == 457	then
		returntable.me_class_name = "ONU time configuration"
	elseif k == 458	then
		returntable.me_class_name = "IP host performance monitoring history data part 2"
	elseif k == 459	then
		returntable.me_class_name = "ONU operational performance monitoring history data"
	elseif k == 460	then
		returntable.me_class_name = "ONU4-G"
	elseif k == 461	then
		returntable.me_class_name = "BBF TR-369 USP agent"
	elseif k == 462	then
		returntable.me_class_name = "FAST channel configuration profile, part 2"
	elseif k == 463	then
		returntable.me_class_name = "FAST line failures performance monitoring data"
	elseif k == 464	then
		returntable.me_class_name = "Synchronous Ethernet operation"
	elseif k == 465	then
		returntable.me_class_name = "Precision Time Protocol"
	elseif k == 466	then
		returntable.me_class_name = "Precision Time Protocol status"
	elseif k >= 467 and k <= 65279	then
		returntable.me_class_name = "Reserved for future standardization"
	elseif k >= 65280 and k <= 65535 then
		returntable.me_class_name = "Reserved for vendor-specific use"
	else
		returntable.me_class_name= "***TBD*** (" .. k .. ")"
    end
	return returntable
  end
}

local omci_def = {
	[2] = {
		me_class_name = "ONU Data",
		{ attname="MIB Data Sync", length=1, setbycreate=false },
	},

	[5] = { me_class_name = "Cardholder",
		{ attname="Actual Plug-in Unit Type", length=1, setbycreate=false },
		{ attname="Expected Plug-in Unit Type", length=1, setbycreate=false },
		{ attname="Expected Port Count", length=1, setbycreate=false },
		{ attname="Expected Equipment Id", length=20, setbycreate=false },
		{ attname="Actual Equipment Id", length=20, setbycreate=false },
		{ attname="Protection Profile Pointer", length=1, setbycreate=false },
		{ attname="Invoke Protection Switch", length=1, setbycreate=false }},

	[6] = { me_class_name = "Circuit Pack",
		{ attname="Type", length=1, setbycreate=true },
		{ attname="Number of ports", length=1, setbycreate=false },
		{ attname="Serial Number", length=8, setbycreate=false },
		{ attname="Version", length=14, setbycreate=false },
		{ attname="Vendor Id", length=4, setbycreate=false },
		{ attname="Administrative State", length=1, setbycreate=true },
		{ attname="Operational State", length=1, setbycreate=false },
		{ attname="Bridged or IP Ind", length=1, setbycreate=false },
		{ attname="Equipment Id", length=20, setbycreate=false },
		{ attname="Card Configuration", length=1, setbycreate=true },
		{ attname="Total T-CONT Buffer Number", length=1, setbycreate=false },
		{ attname="Total Priority Queue Number", length=1, setbycreate=false },
		{ attname="Total Traffic Scheduler Number", length=1, setbycreate=false },
		{ attname="Power Shed Override", length=4, setbycreate=false }},

	[7] = { me_class_name = "Software Image",
		{ attname="Version", length=14, setbycreate=false },
		{ attname="Is committed", length=1, setbycreate=false },
		{ attname="Is active", length=1, setbycreate=false },
		{ attname="Is valid", length=1, setbycreate=false }},

	[11] = { me_class_name = "Physical path termination point Ethernet UNI",
		{attname="Expected Type",			length=1, setbycreate=false},
		{attname="Sensed Type",				length=1, setbycreate=false},
		{attname="Auto Detection Configuration",	length=1, setbycreate=false},
		{attname="Ethernet Loopback Configuration",	length=1, setbycreate=false},
		{attname="Administrative State",		length=1, setbycreate=false},
		{attname="Operational State",			length=1, setbycreate=false},
		{attname="Configuration Ind",			length=1, setbycreate=false},
		{attname="Max Frame Size",			length=2, setbycreate=false},
		{attname="DTE or DCE",				length=1, setbycreate=false},
		{attname="Pause Time",				length=2, setbycreate=false},
		{attname="Bridged or IP Ind",			length=1, setbycreate=false},
		{attname="ARC",					length=1, setbycreate=false},
		{attname="ARC Interval",			length=1, setbycreate=false},
		{attname="PPPoE Filter",			length=1, setbycreate=false},
		{attname="Power Control",			length=1, setbycreate=false}},

	[24] = { me_class_name = "Ethernet performance monitoring history data",
		{ attname="Interval End Time", length=1, setbycreate=false },
		{ attname="Threshold Data 1/2 Id", length=2, setbycreate=true },
		{ attname="FCS errors Drop events", length=4, setbycreate=false },
		{ attname="Excessive Collision Counter", length=4, setbycreate=false },
		{ attname="Late Collision Counter", length=4, setbycreate=false },
		{ attname="Frames too long", length=4, setbycreate=false },
		{ attname="Buffer overflows on Receive", length=4, setbycreate=false },
		{ attname="Buffer overflows on Transmit", length=4, setbycreate=false },	
		{ attname="Single Collision Frame Counter", length=4, setbycreate=false },	
		{ attname="Multiple Collisions Frame Counter", length=4, setbycreate=false },
		{ attname="SQE counter", length=4, setbycreate=false },
		{ attname="Deferred Transmission Counter", length=4, setbycreate=false },
		{ attname="Internal MAC Transmit Error Counter", length=4, setbycreate=false },
		{ attname="Carrier Sense Error Counter", length=4, setbycreate=false },
		{ attname="Alignment Error Counter", length=4, setbycreate=false },
		{ attname="Internal MAC Receive Error Counter", length=4, setbycreate=false}},

	[44] = { me_class_name = "Vendor Specific",
		{ attname="Sub-Entity", length=1, setbycreate=true },
		subentity_attr = {}},
			
	[45] = { me_class_name = "MAC Bridge Service Profile",
		{ attname="Spanning tree ind", length=1, setbycreate=true },
		{ attname="Learning ind", length=1, setbycreate=true },
		{ attname="Port bridging ind", length=1, setbycreate=true },
		{ attname="Priority", length=2, setbycreate=true },
		{ attname="Max age", length=2, setbycreate=true },
		{ attname="Hello time", length=2, setbycreate=true },
		{ attname="Forward delay", length=2, setbycreate=true },
		{ attname="Unknown MAC address discard", length=1, setbycreate=true },
		{ attname="MAC learning depth", length=1, setbycreate=true }},

	[47] = { me_class_name = "MAC bridge port configuration data",
		{ attname="Bridge id pointer", length=2, setbycreate=true },
		{ attname="Port num", length=1, setbycreate=true },
		{ attname="TP type", length=1, setbycreate=true },
		{ attname="TP pointer", length=2, setbycreate=true },
		{ attname="Port priority", length=2, setbycreate=true },
		{ attname="Port path cost", length=2, setbycreate=true },
		{ attname="Port spanning tree ind", length=1, setbycreate=true },
		{ attname="Encapsulation method", length=1, setbycreate=true },
		{ attname="LAN FCS ind", length=1, setbycreate=true },
		{ attname="Port MAC address", length=6, setbycreate=false },
		{ attname="Outbound TD pointer", length=2, setbycreate=false },
		{ attname="Inbound TD pointer", length=2, setbycreate=false }},

	[48] = { me_class_name = "MAC bridge port designation data",
		{ attname="Designated bridge root cost port", length=24, setbycreate=false },
		{ attname="Port state", length=1, setbycreate=false }},

	[49] = { me_class_name = "MAC bridge port filter table data",
		{ attname="MAC filter table", length=8, setbycreate=false }},

	[51] = { me_class_name = "MAC bridge performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1/2 id", length=2, setbycreate=true },
		{ attname="Bridge learning entry discard count", length=4, setbycreate=false }},

	[52] = { me_class_name = "MAC bridge port performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1/2 id", length=2, setbycreate=true },
		{ attname="Forwarded frame counter", length=4, setbycreate=false },	
		{ attname="Delay exceeded discard counter", length=4, setbycreate=false },	
		{ attname="MTU exceeded discard counter", length=4, setbycreate=false },	
		{ attname="Received frame counter", length=4, setbycreate=false },	
		{ attname="Received and discarded counter", length=4, setbycreate=false }},

	[79] = { me_class_name = "MAC bridge port filter pre-assign table",
		{ attname="IPv4 multicast filtering", length=1, setbycreate=false },
		{ attname="IPv6 multicast filtering", length=1, setbycreate=false },
		{ attname="IPv4 broadcast filtering", length=1, setbycreate=false },
		{ attname="RARP filtering", length=1, setbycreate=false },
		{ attname="IPX filtering", length=1, setbycreate=false },
		{ attname="NetBEUI filtering", length=1, setbycreate=false },
		{ attname="AppleTalk filtering", length=1, setbycreate=false },
		{ attname="Bridge management information filtering", length=1, setbycreate=false },
		{ attname="ARP filtering", length=1, setbycreate=false }},

	[82] = { me_class_name = "Physical path termination point video UNI",
		{attname="Administrative State", length=1, setbycreate=false},
		{attname="Operational State", length=1, setbycreate=false},
		{attname="ARC",	length=1, setbycreate=false},
		{attname="ARC Interval", length=1, setbycreate=false},
		{attname="Power Control", length=1, setbycreate=false}},
		
	[84] = { me_class_name = "VLAN tagging filter data",
		{attname="VLAN filter list", length=24, setbycreate=true},
		{attname="Forward operation", length=1, setbycreate=true},
		{attname="Number of entries",	length=1, setbycreate=true}},

	[89] = { me_class_name = "Ethernet performance monitoring history data 2",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1/2 id", length=2, setbycreate=true },
		{ attname="PPPoE filtered frame counter", length=4, setbycreate=false }},
		
	[90] = { me_class_name = "Physical path termination point video ANI",
		{attname="Administrative State", length=1, setbycreate=false},
		{attname="Operational State", length=1, setbycreate=false},
		{attname="ARC",	length=1, setbycreate=false},
		{attname="ARC Interval", length=1, setbycreate=false},
		{attname="Frequency Range Low", length=1, setbycreate=false},
		{attname="Frequency Range High", length=1, setbycreate=false},
		{attname="Signal Capability", length=1, setbycreate=false},
		{attname="Optical Signal Level", length=1, setbycreate=false},
		{attname="Pilot Signal Level", length=1, setbycreate=false},
		{attname="Signal Level min", length=1,	setbycreate=false},
		{attname="Signal Level max", length=1,	setbycreate=false},
		{attname="Pilot Frequency", length=4,	setbycreate=false},
		{attname="AGC Mode", length=1,	setbycreate=false},
		{attname="AGC Setting", length=1,	setbycreate=false},	
		{attname="Video Lower Optical Threshold", length=1, setbycreate=false},
		{attname="Video Upper Optical Threshold", length=1, setbycreate=false}},
	 
	 [130] = { me_class_name = "IEEE 802.1p mapper service profile",
		{attname="TP Pointer",					length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 0",	length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 1",	length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 2",	length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 3",	length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 4",	length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 5",	length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 6",	length=2,  setbycreate=true},
		{attname="Interwork TP pointer for P-bit priority 7",	length=2,  setbycreate=true},
		{attname="Unmarked frame option:",		length=1,  setbycreate=true},
		{attname="DSCP to P-bit mapping",		length=24, setbycreate=false},
		{attname="Default P-bit marking",		length=1,  setbycreate=true},
		{attname="TP Type:",					length=1,  setbycreate=true}},

	[131] = { me_class_name = "OLT-G",
		{attname="OLT vendor id",					length=4,  setbycreate=false},
		{attname="Equipment id",	length=20,  setbycreate=false},
		{attname="OLT version",	length=14,  setbycreate=false}},
					
	[133] = { me_class_name = "ONU Power Shedding",
		{ attname="Restore power timer reset interval", length=2, setbycreate=false },
		{ attname="Data class shedding interval", length=2, setbycreate=false },
		{ attname="Voice class shedding interval", length=2, setbycreate=false },
		{ attname="Video overlay class shedding interval", length=2, setbycreate=false },
		{ attname="Video return class shedding interval", length=2, setbycreate=false },
		{ attname="DSL class shedding interval", length=2, setbycreate=false },
		{ attname="ATM class shedding interval", length=2, setbycreate=false },
		{ attname="CES class shedding interval", length=2, setbycreate=false },
		{ attname="Frame class shedding interval", length=2, setbycreate=false },
		{ attname="SONET class shedding interval", length=2, setbycreate=false },
		{ attname="Shedding status", length=2, setbycreate=false }},


	[134] = { 
		me_class_name = "IP host config data",
		{ attname="IP options", length=1, setbycreate=false },
		{ attname="MAC address", length=6, setbycreate=false },
		{ attname="Onu identifier", length=25, setbycreate=false },
		{ attname="IP address", length=4, setbycreate=false },
		{ attname="Mask", length=4, setbycreate=false },
		{ attname="Gateway", length=4, setbycreate=false },
		{ attname="Primary DNS", length=4, setbycreate=false },
		{ attname="Secondary DNS", length=4, setbycreate=false },
		{ attname="Current address", length=4, setbycreate=false },
		{ attname="Current Mask", length=4, setbycreate=false },
		{ attname="Current Gateway", length=4, setbycreate=false },
		{ attname="Current Primary DNS", length=4, setbycreate=false },
		{ attname="Current Secondary DNS", length=4, setbycreate=false },
		{ attname="Domain name", length=25, setbycreate=false },
		{ attname="Host name", length=25, setbycreate=false },
		{ attname="Relay agent options", length=2, setbycreate=false },
	},

	[137] = { me_class_name = "Network address",
		{ attname="Security pointer", length=2, setbycreate=true },
		{ attname="Address pointer", length=2, setbycreate=true }},

	[140] = { me_class_name = "Call control performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1 ID", length=2, setbycreate=true }},
		
	[144] = { me_class_name = "RTP performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1 ID", length=2, setbycreate=true }},

	[157] = { me_class_name = "Large string",
		{ attname="Number of parts", length=1, setbycreate=true },
		{ attname="Part 1", length=25, setbycreate=false }},

	[158] = { me_class_name = "ONU remote debug",
		{ attname="Command format", length=1, setbycreate=false },
		{ attname="Command", length=25, setbycreate=false },
		{ attname="Reply table", length=4, setbycreate=false }},

	[159] = { me_class_name = "Equipment protection profile",
		{ attname="Protect slot 1,protect slot 2", length=2, setbycreate=true },
		{ attname="working slot 1,working slot 2,working slot 3,working slot 4,working slot 5,working slot 6,working slot 7,working slot 8", length=8, setbycreate=true },
		{ attname="Protect status 1,protect status 2", length=2, setbycreate=false },
		{ attname="Revertive ind", length=1, setbycreate=true },
		{ attname="Wait to restore time", length=1, setbycreate=true }},

	[160] = { me_class_name = "Equipment extension package",
		{ attname="Environmental sense", length=2, setbycreate=false },
		{ attname="Contact closure output", length=2, setbycreate=false }},

	[171] = { me_class_name = "Extended VLAN tagging operation configuration data",
		{ attname="Association type", length=1, setbycreate=true },
		{ attname="Received frame VLAN tagging operation table max size", length=2, setbycreate=false },
		{ attname="Input TPID", length=2, setbycreate=false },
		{ attname="Output TPID", length=2, setbycreate=false },	
		{ attname="Downstream mode", length=1, setbycreate=false },
		{ attname="Received frame VLAN tagging operation table", length=16, setbycreate=false },
		{ attname="Associated ME pointer", length=2, setbycreate=true },
		{ attname="DSCP to P-bit mapping", length=24, setbycreate=false }},
		
	[256] = { me_class_name = "ONU-G",
		{ attname="Vendor Id", length=4, setbycreate=false },
		{ attname="Version", length=14, setbycreate=false },
		{ attname="Serial Nr", length=8, setbycreate=false },
		{ attname="Traffic management option", length=1, setbycreate=false },
		{ attname="VP/VC cross connection function option", length=1, setbycreate=false },
		{ attname="Battery backup", length=1, setbycreate=false },
		{ attname="Administrative State", length=1, setbycreate=false },
		{ attname="Operational State", length=1, setbycreate=false }},

	[257] = { me_class_name = "ONU2-G",
		{ attname="Equipment id", length=20, setbycreate=false },
		{ attname="OMCC version", length=1, setbycreate=false },
		{ attname="Vendor product code", length=2, setbycreate=false },
		{ attname="Security capability", length=1, setbycreate=false },
		{ attname="Security mode", length=1, setbycreate=false },
		{ attname="Total priority queue number", length=2, setbycreate=false },
		{ attname="Total traffic scheduler number", length=1, setbycreate=false },
		{ attname="Mode", length=1, setbycreate=false },
		{ attname="Total GEM port-ID number", length=2, setbycreate=false },
		{ attname="SysUp Time", length=4, setbycreate=false }},

	[262] = { me_class_name = "T-CONT",
		{ attname="Alloc-id", length=2, setbycreate=false },
		{ attname="Mode indicator", length=1, setbycreate=false },
		{ attname="Policy", length=1, setbycreate=false }},

	[263] = { me_class_name = "ANI-G",
		{ attname="SR indication", length=1, setbycreate=false },
		{ attname="Total T-CONT number", length=2, setbycreate=false },
		{ attname="GEM block length", length=2, setbycreate=false },
		{ attname="Piggyback DBA reporting", length=1, setbycreate=false },
		{ attname="Whole ONT DBA reporting", length=1, setbycreate=false },
		{ attname="SF threshold", length=1, setbycreate=false },
		{ attname="SD threshold", length=1, setbycreate=false },
		{ attname="ARC", length=1, setbycreate=false },
		{ attname="ARC interval", length=1, setbycreate=false },
		{ attname="Optical signal level", length=2, setbycreate=false },
		{ attname="Lower optical threshold", length=1, setbycreate=false },
		{ attname="Upper optical threshold", length=1, setbycreate=false },
		{ attname="ONT response time", length=2, setbycreate=false },
		{ attname="Transmit optical level", length=2, setbycreate=false },
		{ attname="Lower transmit power threshold", length=1, setbycreate=false },
		{ attname="Upper transmit power threshold", length=1, setbycreate=false }},

	[264] = { me_class_name = "UNI-G",
		{ attname="Config option status", length=2, setbycreate=false },
		{ attname="Administrative state", length=1, setbycreate=false }},
		
	[266] = { me_class_name = "GEM interworking Termination Point",
		{ attname="GEM port network CTP connectivity pointer", length=2, setbycreate=true },
		{ attname="Interworking option", length=1, setbycreate=true },
		{ attname="Service profile pointer", length=2, setbycreate=true },
		{ attname="Interworking termination point pointer", length=2, setbycreate=true },
		{ attname="PPTP counter", length=1, setbycreate=false },
		{ attname="Operational state", length=1, setbycreate=false },
		{ attname="GAL profile pointer", length=2, setbycreate=true },
		{ attname="GAL loopback configuration", length=1, setbycreate=false }},


	[268] = { me_class_name = "GEM Port Network CTP",
		{ attname="Port id value", length=2, setbycreate=true },
		{ attname="T-CONT pointer", length=2, setbycreate=true },
		{ attname="Direction", length=1, setbycreate=true },
		{ attname="Traffic management pointer for upstream", length=2, setbycreate=true },
		{ attname="Traffic descriptor profile pointer", length=2, setbycreate=true },
		{ attname="UNI counter", length=1, setbycreate=false },
		{ attname="Priority queue pointer for downstream", length=2, setbycreate=true },
		{ attname="Encryption state", length=1, setbycreate=false }},

	[271] = { me_class_name = "GAL TDM profile",
		{ attname="GEM frame loss integration period", length=2, setbycreate=true }},

	[272] = { me_class_name = "GAL Ethernet profile",
		{ attname="Maximum GEM payload size", length=2, setbycreate=true }},

	[273] = { me_class_name = "Threshold Data 1",
		{attname="Threshold value 1",	length=4,  setbycreate=true},
		{attname="Threshold value 2",	length=4,  setbycreate=true},
		{attname="Threshold value 3",	length=4,  setbycreate=true},
		{attname="Threshold value 4",	length=4,  setbycreate=true},
		{attname="Threshold value 5",	length=4,  setbycreate=true},
		{attname="Threshold value 6",	length=4,  setbycreate=true},
		{attname="Threshold value 7",	length=4,  setbycreate=true}},

	[274] = { me_class_name = "Threshold Data 2",
		{attname="Threshold value 8",	length=4,  setbycreate=true},
		{attname="Threshold value 9",	length=4,  setbycreate=true},
		{attname="Threshold value 10",	length=4,  setbycreate=true},
		{attname="Threshold value 11",	length=4,  setbycreate=true},
		{attname="Threshold value 12",	length=4,  setbycreate=true},
		{attname="Threshold value 13",	length=4,  setbycreate=true},
		{attname="Threshold value 14",	length=4,  setbycreate=true}},


	[276] = { me_class_name = "GAL Ethernet performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1/2 id", length=2, setbycreate=true },
		{ attname="Discarded frames", length=4, setbycreate=false }},

	[277] = { me_class_name = "Priority queue",
		{attname="Queue Configuration Option",		length=1,  setbycreate=false},
		{attname="Maximum Queue Size",			length=2,  setbycreate=false},
		{attname="Allocated Queue Size",		length=2,  setbycreate=false},
		{attname="Discard-block Counter Reset Interval",length=2,  setbycreate=false},
		{attname="Threshold Value For Discarded Blocks Due To Buffer Overflow",	length=2,  setbycreate=false},
		{attname="Related Port",			length=4,  setbycreate=false},
		{attname="Traffic Scheduler-G Pointer",		length=2,  setbycreate=false},
		{attname="Weight",				length=1,  setbycreate=false},
		{attname="Back Pressure Operation",		length=2,  setbycreate=false},
		{attname="Back Pressure Time",			length=4,  setbycreate=false},
		{attname="Back Pressure Occur Queue Threshold",	length=2,  setbycreate=false},
		{attname="Back Pressure Clear Queue Threshold",	length=2,  setbycreate=false}},

	[278] = { me_class_name = "Traffic scheduler",
		{ attname="TCONT pointer", length=2, setbycreate=false },
		{ attname="traffic shed pointer", length=2, setbycreate=false },
		{ attname="policy", length=1, setbycreate=false },
		{ attname="priority/weight", length=1, setbycreate=false }},
		
	[279] = { me_class_name = "Protection data",
		{ attname="Working ANI-G pointer", length=2, setbycreate=false },
		{ attname="Protection ANI-G pointer", length=2, setbycreate=false },
		{ attname="Protection type", length=2, setbycreate=false },
		{ attname="Revertive ind", length=1, setbycreate=false },
		{ attname="Wait to restore time", length=1, setbycreate=false },
		{ attname="Switching guard time", length=2, setbycreate=false }},

	[281] = { me_class_name = "Multicast GEM interworking termination point",
		{ attname="GEM port network CTP connectivity pointer", length=2, setbycreate=true },
		{ attname="Interworking option", length=1, setbycreate=true },
		{ attname="Service profile pointer", length=2, setbycreate=true },
		{ attname="Interworking termination point pointer", length=2, setbycreate=true },
		{ attname="PPTP counter", length=1, setbycreate=false },
		{ attname="Operational state", length=1, setbycreate=false },
		{ attname="GAL profile pointer", length=2, setbycreate=true },
		{ attname="GAL loopback configuration", length=1, setbycreate=true },
		{ attname="Multicast address table", length=12, setbycreate=false }},

	[287] = { me_class_name = "OMCI",
		{ attname="ME Type Table", length=2, setbycreate=false },
		{ attname="Message Type Table", length=2, setbycreate=false }},


	[290] = { me_class_name = "Dot1X Port Extension Package",
		{ attname="Dot1x Enable", length=1, setbycreate=false },
		{ attname="Action Register", length=1, setbycreate=false },
		{ attname="Authenticator PAE State", length=1, setbycreate=false },
		{ attname="Backend Authentication State", length=1, setbycreate=false },
		{ attname="Admin Controlled Directions", length=1, setbycreate=false },
		{ attname="Operational Controlled Directions", length=1, setbycreate=false },
		{ attname="Authenticator Controlled Port Status", length=1, setbycreate=false },
		{ attname="Quiet Period", length=2, setbycreate=false },
		{ attname="Server Timeout Period", length=2, setbycreate=false },
		{ attname="Reauthentication Period", length=2, setbycreate=false },
		{ attname="Reauthentication Enabled", length=1, setbycreate=false },
		{ attname="Key transmission Enabled", length=1, setbycreate=false }},

	[292] = { me_class_name = "Dot1X performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1 ID", length=2, setbycreate=true }},

	[296] = { me_class_name = "Ethernet performance monitoring history data 3",
		{ attname="Interval End Time", length=1, setbycreate=false },
		{ attname="Threshold Data 1/2 Id", length=2, setbycreate=true },
		{ attname="Drop events", length=4, setbycreate=false },
		{ attname="Octets", length=4, setbycreate=false },
		{ attname="Packets", length=4, setbycreate=false },
		{ attname="Broadcast Packets", length=4, setbycreate=false },
		{ attname="Multicast Packets", length=4, setbycreate=false },
		{ attname="Undersize Packets", length=4, setbycreate=false },	
		{ attname="Fragments", length=4, setbycreate=false },	
		{ attname="Jabbers", length=4, setbycreate=false },	
		{ attname="Packets 64 Octets", length=4, setbycreate=false },
		{ attname="Packets 65 to 127 Octets", length=4, setbycreate=false },
		{ attname="Packets 128 to 255 Octets", length=4, setbycreate=false },
		{ attname="Packets 256 to 511 Octets", length=4, setbycreate=false },
		{ attname="Packets 512 to 1023 Octets", length=4, setbycreate=false },
		{ attname="Packets 1024 to 1518 Octets", length=4, setbycreate=false }},
		
	[297] = { me_class_name = "Port-mapping package",
		{ attname="Max ports", length=1, setbycreate=false },
		{ attname="Port list 1", length=16, setbycreate=false },
		{ attname="Port list 2", length=16, setbycreate=false },
		{ attname="Port list 3", length=16, setbycreate=false },
		{ attname="Port list 4", length=16, setbycreate=false },
		{ attname="Port list 5", length=16, setbycreate=false },
		{ attname="Port list 6", length=16, setbycreate=false },
		{ attname="Port list 7", length=16, setbycreate=false },
		{ attname="Port list 8", length=16, setbycreate=false }},

	[309] = { me_class_name = "Multicast operations profile",
		{ attname="IGMP version", length=1, setbycreate=true },
		{ attname="IGMP function", length=1, setbycreate=true },
		{ attname="Immediate leave", length=1, setbycreate=true },
		{ attname="Upstream IGMP TCI", length=2, setbycreate=true },
		{ attname="Upstream IGMP tag control", length=1, setbycreate=true },
		{ attname="Upstream IGMP rate", length=4, setbycreate=true },
		{ attname="Dynamic access control list table", length=24, setbycreate=false },
		{ attname="Static access control list table", length=24, setbycreate=false },	
		{ attname="Lost groups list table", length=10, setbycreate=false },		
		{ attname="Robustness", length=1, setbycreate=true },	
		{ attname="Querier IP address", length=4, setbycreate=true },		
		{ attname="Query interval", length=4, setbycreate=true },		
		{ attname="Query max response time", length=4, setbycreate=true },		
		{ attname="Last member query interval", length=4, setbycreate=false }},

	[310] = { me_class_name = "Multicast subscriber config info",
		{ attname="ME type", length=1, setbycreate=true },
		{ attname="Multicast operations profile pointer", length=2, setbycreate=true },
		{ attname="Max simultaneous groups", length=2, setbycreate=true },
		{ attname="Max multicast bandwidth", length=4, setbycreate=true },
		{ attname="Bandwidth enforcement", length=1, setbycreate=true }},	
		
	[311] = { me_class_name = "Multicast subscriber monitor",
		{ attname="ME type", length=1, setbycreate=true },
		{ attname="Current multicast bandwidth", length=4, setbycreate=false },
		{ attname="Max Join messages counter", length=4, setbycreate=false },
		{ attname="Bandwidth exceeded counter:", length=4, setbycreate=false },
		{ attname="Active group list table", length=24, setbycreate=false }},	

	[312] = { me_class_name = "FEC performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1/2 id", length=2, setbycreate=true },
		{ attname="Corrected bytes", length=4, setbycreate=false },
		{ attname="Corrected code words", length=4, setbycreate=false },
		{ attname="Uncorrectable code words", length=4, setbycreate=false },
		{ attname="Total code words", length=4, setbycreate=false },
		{ attname="FEC seconds", length=2, setbycreate=false }},

	[321] = { me_class_name = "Ethernet frame performance monitoring history data downstream",
		{ attname="Interval End Time", length=1, setbycreate=false },
		{ attname="Threshold Data 1/2 Id", length=2, setbycreate=true },
		{ attname="Drop events", length=4, setbycreate=false },
		{ attname="Octets", length=4, setbycreate=false },
		{ attname="Packets", length=4, setbycreate=false },
		{ attname="Broadcast Packets", length=4, setbycreate=false },
		{ attname="Multicast Packets", length=4, setbycreate=false },
		{ attname="CRC Errored Packets", length=4, setbycreate=false },	
		{ attname="Undersize Packets", length=4, setbycreate=false },	
		{ attname="Oversize Packets", length=4, setbycreate=false },
		{ attname="Packets 64 Octets", length=4, setbycreate=false },
		{ attname="Packets 65 to 127 Octets", length=4, setbycreate=false },
		{ attname="Packets 128 to 255 Octets", length=4, setbycreate=false },
		{ attname="Packets 256 to 511 Octets", length=4, setbycreate=false },
		{ attname="Packets 512 to 1023 Octets", length=4, setbycreate=false },
		{ attname="Packets 1024 to 1518 Octets", length=4, setbycreate=false }},

	[322] = { me_class_name = "Ethernet frame performance monitoring history data upstream",
		{ attname="Interval End Time", length=1, setbycreate=false },
		{ attname="Threshold Data 1/2 Id", length=2, setbycreate=true },
		{ attname="Drop events", length=4, setbycreate=false },
		{ attname="Octets", length=4, setbycreate=false },
		{ attname="Packets", length=4, setbycreate=false },
		{ attname="Broadcast Packets", length=4, setbycreate=false },
		{ attname="Multicast Packets", length=4, setbycreate=false },
		{ attname="CRC Errored Packets", length=4, setbycreate=false },	
		{ attname="Undersize Packets", length=4, setbycreate=false },	
		{ attname="Oversize Packets", length=4, setbycreate=false },
		{ attname="Packets 64 Octets", length=4, setbycreate=false },
		{ attname="Packets 65 to 127 Octets", length=4, setbycreate=false },
		{ attname="Packets 128 to 255 Octets", length=4, setbycreate=false },
		{ attname="Packets 256 to 511 Octets", length=4, setbycreate=false },
		{ attname="Packets 512 to 1023 Octets", length=4, setbycreate=false },
		{ attname="Packets 1024 to 1518 Octets", length=4, setbycreate=false }},


	[329] = { 
	    me_class_name = "Virtual Ethernet interface point",
		{ attname="Administrative state", length=1, setbycreate=false },
		{ attname="Operational state", length=1, setbycreate=false },
		{ attname="Interdomain name", length=25, setbycreate=false },
		{ attname="TCP/UDP pointer", length=2, setbycreate=false },
		{ attname="IANA assigned port", length=2, setbycreate=false },
	},


	[332] = { 
	    me_class_name = "Enhanced security control",
		{ attname="OLT crypto capabilities", length=16, setbycreate=false },
		{ attname="OLT random challenge table", length=17, setbycreate=false },
		{ attname="OLT challenge status", length=1, setbycreate=false },
		{ attname="ONU selected crypto capabilities", length=1, setbycreate=false },
		{ attname="ONU random challenge table", length=16, setbycreate=false },
		{ attname="ONU authentication result table", length=16, setbycreate=false },
		{ attname="OLT authentication result table", length=17, setbycreate=false },
		{ attname="OLT result status", length=1, setbycreate=false },
		{ attname="ONU authentication status", length=1, setbycreate=false },
		{ attname="Master session key name", length=16, setbycreate=false },
		{ attname="Broadcast key table", length=18, setbycreate=false },
		{ attname="Effective key length", length=2, setbycreate=false },
	},



	[334] = { me_class_name = "Ethernet frame extended PM",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1 ID", length=2, setbycreate=true },
		{ attname="Parent ME class", length=2, setbycreate=true },
		{ attname="Parent ME instance", length=2, setbycreate=true },
		{ attname="Accumulation disable", length=2, setbycreate=true },
		{ attname="TCA disable", length=2, setbycreate=true },
		{ attname="Control fields", length=2, setbycreate=true },
		{ attname="TCI", length=2, setbycreate=true },
		{ attname="Reserved", length=2, setbycreate=true }},

	[340] = { 
	    me_class_name = "BBF TR-069 management server",
		{ attname="Administrative state", length=1, setbycreate=false },
		{ attname="ACS network address", length=2, setbycreate=false },
		{ attname="Associated tag", length=2, setbycreate=false },
	},


	[341] = { 
	    me_class_name = "GEM port network CTP performance monitoring history data",
		{ attname="Interval end time", length=1, setbycreate=false },
		{ attname="Threshold data 1 ID", length=2, setbycreate=true },
	},


	[347] = { me_class_name = "IPv6 host config data",
		{ attname="IP options", length=1, setbycreate=false },
		{ attname="MAC address", length=6, setbycreate=false },
		{ attname="IPv6 link local address", length=16, setbycreate=false },
		{ attname="IPv6 address", length=16, setbycreate=false },
		{ attname="Default router", length=16, setbycreate=false },
		{ attname="Primary DNS", length=16, setbycreate=false },
		{ attname="Secondary DNS", length=16, setbycreate=false },
		{ attname="Current address table", length=24, setbycreate=false },
		{ attname="Current default router table", length=16, setbycreate=false },
		{ attname="Current DNS table", length=16, setbycreate=false },
		{ attname="DUID", length=25, setbycreate=false },
		{ attname="On-link prefix", length=17, setbycreate=false },
		{ attname="Current on-link prefix table", length=26, setbycreate=false },
		{ attname="Relay agent options", length=2, setbycreate=false },
	},
}

setmetatable(omci_def, mt2)

-- GUI field definition
local f = omciproto.fields
f.tci = ProtoField.uint16("omciproto.tci", "Transaction Correlation ID")
f.msg_type_db = ProtoField.uint8("omciproto.msg_type_db", "reserved", base.HEX, nil, 0x80)
f.msg_type_ar = ProtoField.uint8("omciproto.msg_type_ar", "AR", base.HEX, nil, 0x40)
f.msg_type_ak = ProtoField.uint8("omciproto.msg_type_ak", "AK", base.HEX, nil, 0x20)
f.msg_type_mt = ProtoField.uint8("omciproto.msg_type_mt", "Message Type", base.DEC, msgtype, 0x1F)
f.dev_id = ProtoField.uint8("omciproto.dev_id", "Device Identifier", base.HEX)
f.me_id = ProtoField.uint16("omciproto.me_id", "Managed Entity Instance", base.HEX)
f.me_class = ProtoField.uint16("omciproto.me_class", "Managed Entity Class", base.DEC) 
f.attribute_mask = ProtoField.uint16("omciproto.attribtute_mask", "Attribute Mask", base.HEX, nil, 0xFFFF)
f.attribute = ProtoField.bytes("omciproto.attribute", "Attribute")
f.content = ProtoField.bytes("omciproto.content", "Message Content")
f.trailer = ProtoField.bytes("omciproto.trailer", "Trailer")
f.cpcsuu_cpi = ProtoField.uint16("omciproto.cpcsuu_cpi", "CPCS-UU and CPI", base.HEX)
f.cpcssdu_length = ProtoField.uint16("omciproto.cpcssdu_length", "CPCS-SDU Length", base.HEX)
f.crc32 = ProtoField.uint32("omciproto.crc32", "CRC32", base.HEX)

-- The dissector function
function omciproto.dissector (buffer, pinfo, tree)
	if buffer:len() == 0 then return end -- validate packet length is adequate, otherwise quit

	-- Show name of the protocol, create Tree item for displaying info
	pinfo.cols.protocol = omciproto.name
	local subtree = tree:add(omciproto, buffer())

	-- Start analysing data
	local offset = 0
	
	-- OMCI Transaction Correlation Identifier
	local tci = buffer(offset, 2)
	subtree:add(f.tci, tci)
	offset = offset +  2
	
	-- OMCI Message Type
	local msg_type = buffer(offset, 1)
	local msg_type_mt = msgtype[msg_type:bitfield(3,5)]
	local msg_type_ar = msg_type:bitfield(1,1)
	local msg_type_ak = msg_type:bitfield(2,1)
	local msgtype_subtree = subtree:add(msg_type, "Message Type = " .. msg_type_mt)
	msgtype_subtree:add(f.msg_type_db, msg_type)
	msgtype_subtree:add(f.msg_type_ar, msg_type)
	msgtype_subtree:add(f.msg_type_ak, msg_type)
	msgtype_subtree:add(f.msg_type_mt, msg_type)
	offset = offset +  1
	
	-- OMCI Device ID
	local dev_id = buffer(offset, 1)
	subtree:add(f.dev_id, dev_id)
	offset = offset +  1
	
	-- OMCI Message Entity Class & Instance
	local me_class = buffer(offset, 2)
	local me_instance = buffer(offset + 2, 2)
	local me_class_name = omci_def[me_class:uint()].me_class_name
	
	local devid_subtree = subtree:add(buffer(offset, 4), "Message Identifier, ME Class = " .. me_class_name .. ", Instance = 0x" .. me_instance)
	devid_subtree:add(f.me_class,  me_class:uint())
	devid_subtree:add(f.me_id, me_instance)
	offset = offset +  4
	
	-- OMCI Attributes and/or message result	
	local content = buffer(offset, 32)
	if( (msg_type_mt == "Get" or msg_type_mt == "Get Current Data") and msg_type_ar == 1 and msg_type_ak == 0) then
		local attribute_mask = content(0, 2)
		local attributemask_subtree = subtree:add(attribute_mask, "Attribute Mask (0x" .. attribute_mask .. ")" )
		attributemask_subtree:add(attribute_mask, tostring(BinDecHex.Hex2Bin(tostring(attribute_mask))))
		local content_subtree = subtree:add(content, "Attribute List")
		attributes = omci_def[me_class:uint()]
		for i = 1,#attributes do
			local attr = attributes[i]
			if attribute_mask:bitfield(i-1,1) == 1 then
				content_subtree:add(string.format("%2.2d", i) .. ": " .. attr.attname)
			end
		end
	end

	if( (msg_type_mt == "Get" or msg_type_mt == "Get Current Data") and msg_type_ar == 0 and msg_type_ak == 1) then
		subtree:add(content(0,1), "Result: " .. msg_result[content(0,1):uint()] .. " (" .. content(0,1) .. ")")
		local attribute_mask = content(1, 2)
		local attributemask_subtree = subtree:add(attribute_mask, "Attribute Mask (0x" .. attribute_mask .. ")" )
		attributemask_subtree:add(attribute_mask, tostring(BinDecHex.Hex2Bin(tostring(attribute_mask))))
		local content_subtree = subtree:add(content, "Attribute List")
		local attributes = {}
		local attribute_offset = 0
		attributes = omci_def[me_class:uint()]
		attribute_offset=3
		for i = 1,#attributes do
			local attr = attributes[i]
			if attribute_mask:bitfield(i-1,1) == 1 then
				local attr_bytes = content(attribute_offset, attr.length)
				content_subtree:add(attr_bytes, string.format("%2.2d", i) .. ": " .. attr.attname .. " (" .. attr_bytes .. ")")
				attribute_offset = attribute_offset + attr.length
			end
		end
	end

	if( msg_type_mt == "Set" and msg_type_ar == 1 and msg_type_ak == 0) then
		local attribute_mask = content(0, 2)
		local attributemask_subtree = subtree:add(attribute_mask, "Attribute Mask (0x" .. attribute_mask .. ")" )
		attributemask_subtree:add(attribute_mask, tostring(BinDecHex.Hex2Bin(tostring(attribute_mask))))
		local content_subtree = subtree:add(content, "Attribute List")
		local attributes = {}
		local attribute_offset = 0
		attributes = omci_def[me_class:uint()]
		attribute_offset=2
		for i = 1,#attributes do
			local attr = attributes[i]
			if attribute_mask:bitfield(i-1,1) == 1 then
				local attr_bytes = content(attribute_offset, attr.length)
				content_subtree:add(attr_bytes, string.format("%2.2d", i) .. ": " .. attr.attname .. " (" .. attr_bytes .. ")")
				attribute_offset = attribute_offset + attr.length
			end
		end
	end

	if((msg_type_mt == "Set" or 
		msg_type_mt == "Create" or
		msg_type_mt == "MIB Reset" or 
		msg_type_mt == "Test" ) and msg_type_ar == 0 and msg_type_ak == 1) then
		subtree:add(content(0,1), "Result: " .. msg_result[content(0,1):uint()] .. " (" .. content(0,1) .. ")")
	end

	if( msg_type_mt == "Create" and msg_type_ar == 1 and msg_type_ak == 0) then
		local content_subtree = subtree:add(content, "Attribute List")
		local attributes = {}
		local attribute_offset = 0
		attributes = omci_def[me_class:uint()]
		attribute_offset=0
		for i = 1,#attributes do
			local attr = attributes[i]
			if attr.setbycreate then
				local attr_bytes = content(attribute_offset, attr.length)
				content_subtree:add(attr_bytes, string.format("%2.2d", i) .. ": " .. attr.attname .. " (" .. attr_bytes .. ")")
				attribute_offset = attribute_offset + attr.length
			end
		end
	end

	if(msg_type_mt == "MIB Upload" and msg_type_ar == 0 and msg_type_ak == 1) then
		subtree:add(content(0,2), "Number of subsequent commands: " .. content(0,2):uint() .. " (" .. content(0,2) .. ")")
	end

	if(msg_type_mt == "MIB Upload Next" and msg_type_ar == 1 and msg_type_ak == 0) then
		subtree:add(content(0,2), "Command number: " .. content(0,2):uint() .. " (" .. content(0,2) .. ")")
	end

	if(msg_type_mt == "MIB Upload Next" and msg_type_ar == 0 and msg_type_ak == 1) then
		local upload_substree = subtree:add(content, "ME Class Upload Content")
		local upload_me_class = content(0,2)
		upload_substree:add( upload_me_class, "Managed Entity Class: " .. omci_def[upload_me_class:uint()].me_class_name .. " (" .. upload_me_class:uint() .. ")")
		upload_substree:add(content(2,2), "Managed Entity Instance: " .. content(2,2):uint() .. " (0x" .. content(2,2) .. ")")
		local attribute_mask = content(4, 2)
		local attributemask_subtree = upload_substree:add(attribute_mask, "Attribute Mask (0x" .. attribute_mask .. ")" )
		attributemask_subtree:add(attribute_mask, tostring(BinDecHex.Hex2Bin(tostring(attribute_mask))))
		local content_subtree = upload_substree:add(content, "Attribute List")
		local attributes = {}
		local attribute_offset
		attributes = omci_def[upload_me_class:uint()]
		attribute_offset=6
		for i = 1,#attributes do
			local attr = attributes[i]
			if attribute_mask:bitfield(i-1,1) == 1 then
				local attr_bytes = content(attribute_offset, attr.length)
				content_subtree:add(attr_bytes, string.format("%2.2d", i) .. ": " .. attr.attname .. " (" .. attr_bytes .. ")")
				attribute_offset = attribute_offset + attr.length
			end			
		end
		me_class_name = me_class_name .. " (" .. omci_def[upload_me_class:uint()].me_class_name .. ")"
	end

	if(msg_type_mt == "Test" and msg_type_ar == 1 and msg_type_ak == 0) then
		if( dev_id:uint() == 0x0b) then -- ITU-T G988 XGPON 
			if( me_class:uint() == 263 ) then -- ANI-G
				subtree:add(content(0,2), "Size of message content field: " .. content(0,2))  
				subtree:add(content(2,1), "Test to perform: " .. test_message_name[content(2,1):uint()] .. " (" .. content(2,1) .. ")")
			end
		elseif( dev_id:uint() == 0x0a) then -- ITU-T G984.4 GPON 
			if( me_class:uint() == 263 ) then -- ANI-G
				subtree:add(content(0,1), "Test to perform: " .. test_message_name[content(0,1):uint()] .. " (" .. content(0,1) .. ")")
			end
		end
	end

	if(msg_type_mt == "Test Result" and msg_type_ar == 0 and msg_type_ak == 0 ) then	
		local content_subtree = subtree:add(content, "Test report")
		if( me_class_name == "ANI-G" ) then
			if( content(0,1):uint() == 1 ) then
				content_subtree:add(content(0,3), "Test " .. string.format("%2.2d: ", content(0,1):uint()) .. "Power feed voltage = " .. content(1,2):int() * 20 .. " mV (0x" .. content(1,2) .. ")")
			else
				content_subtree:add_expert_info( PI_MALFORMED, PI_ERROR, "Unexpected 0x" .. content(0,1) .. " test at this location " )
			end
			if( content(3,1):uint() == 3 ) then
				if( content(4,2):int() ~= 0 ) then
					content_subtree:add(content(3,3), "Test " .. string.format("%2.2d: ", content(3,1):uint()) .. "Received optical power = " .. content(4,2):int() * 0.002 - 30 .. " dBm (0x" .. content(4,2) .. ")")		
				else
					content_subtree:add(content(3,3), "Test " .. string.format("%2.2d: ", content(3,1):uint()) .. "Received optical power: Not supported")
				end
			else
				content_subtree:add_expert_info( PI_MALFORMED, PI_ERROR, "Unexpected 0x" .. content(3,1) .. " test at this location " )
			end		
			if( content(6,1):uint() == 5 ) then
				if( content(7,2):int() ~= 0 ) then
					content_subtree:add(content(6,3), "Test " .. string.format("%2.2d: ", content(6,1):uint()) .. "Transmitted optical power = " .. content(7,2):int() * 0.002 - 30 .. " dBm (0x" .. content(7,2) .. ")")		
				else
					content_subtree:add(content(6,3), "Test " .. string.format("%2.2d: ", content(6,1):uint()) .. "Transmitted optical power: Not supported" )
				end
			else
				content_subtree:add_expert_info( PI_MALFORMED, PI_ERROR, "Unexpected 0x" .. content(6,1) .. " test at this location " )
			end		
			if( content(9,1):uint() == 9 ) then
				content_subtree:add(content(9,3), "Test " .. string.format("%2.2d: ", content(9,1):uint()) .. "Laser bias current = " .. content(10,2):int() * 2 .. " uA (0x" .. content(10,2) .. ")")		
			else
				content_subtree:add_expert_info( PI_MALFORMED, PI_ERROR, "Unexpected 0x" .. content(9,1) .. " test at this location " )
			end		
			if( content(12,1):uint() == 12 ) then
				content_subtree:add(content(12,3), "Test " .. string.format("%2.2d: ", content(12,1):uint()) .. "Temperature = " .. content(13,2):int() / 256.0 .. " deg C (0x" .. content(13,2) .. ")")		
			else
				content_subtree:add_expert_info( PI_MALFORMED, PI_ERROR, "Unexpected 0x" .. content(13,1) .. " test at this location " )
			end		
		else
			subtree:add(content, "Test Result for ME Class " .. me_class_name .. " is not implemented!")
		end
	end

	if(msg_type_mt == "Alarm" and msg_type_ar == 0 and msg_type_ak == 0 ) then	
		local alarm_subtree = subtree:add(content(0,27), "Alarms")
		local alarm_set = false
		for i = 0, 27 do --loop through all alarms
			for j = 0, 7 do
				if(content(i,1):bitfield(j,1) == 1) then
					alarm_subtree:add(content(i,1), "Alarm number " .. i*8+j .. " is set")
					alarm_set = true
				end
			end
		end
		if( alarm_set == false) then
			alarm_subtree:add("All alarms cleared")
		end
		alarm_subtree:add(content(28,3), "Padding")
		alarm_subtree:add(content(31,1), "Sequence number: 0x" .. content(31,1) )		
	end
	
	offset = offset + 32
		
	-- OMCI Trailer (if any)
	if( buffer:len() > 46) then
		local trailer = buffer(offset, 8)
		local trailer_subtree = subtree:add(trailer, "Trailer")
		trailer_subtree:add(f.cpcsuu_cpi, trailer(0,2))
		trailer_subtree:add(f.cpcssdu_length, trailer(2,2))
		trailer_subtree:add(f.crc32, trailer(4,4))
	end

	--如果AR为1，则一定是OLT发出的
	if( msg_type_ar == 1 ) then
		msg_type_mt = "OLT> " .. msg_type_mt
	end

	--如果AK为1，则一定是ONU发出的，并且是一个response
	if( msg_type_ak == 1 ) then
		msg_type_mt = "ONU< " .. msg_type_mt .. " response"		
	end

	while msg_type_mt:len() < 30 do  -- Padding to align ME classes
		msg_type_mt = msg_type_mt .. " "
	end
    pinfo.cols.info:set(msg_type_mt .. " - " .. me_class_name)
	subtree:append_text (", " .. msg_type_mt .. " - " .. me_class_name )	-- at the top of the OMCI tree
end

-- Register the dissector
local ether_table = DissectorTable.get( "ethertype" )
ether_table:add(0x8888, omciproto) 

