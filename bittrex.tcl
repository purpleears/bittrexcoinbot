##################################################################################################
# Displays the last, high, low, volume, change from various exchanges and converts them to BTC/USD
# Uses the official data API from Bitstamp, btc-e, and Bittrex (not a screen scraper)
#
# Requirements: TLS, JSON, TCL 8.5
# Tested: Eggdrop 1.8.0+
#
# Instructions: Place bittrex.tcl in your eggdrop /scripts directory @ source it in eggdrop.conf 
# (git clone https://github.com/kitaco/bittrexcoinbot.git)
# Usage: !bittrex <coin>
#################################################################################################

package require Tcl 8.5
package require http
package require tls
package require json

http::register https 443 [list ::tls::socket -require 0 -request 1]

proc s:wget { url } {
   http::config -useragent "Mozilla/EggdropWget"
   catch {set token [http::geturl $url -binary 1 -timeout 10000]} error
   if {![string match -nocase "::http::*" $error]} {
      putserv "PRIVMSG $chan: Error: [string totitle [string map {"\n" " | "} $error]] \( $url \)"
      s:debug "Error: [string totitle [string map {"\n" " | "} $error]] \( $url \)"
      return 0
   }
   if {![string equal -nocase [::http::status $token] "ok"]} {
      putserv "PRIVMSG $chan: Http error: [string totitle [::http::status $token]] \( $url \)"
      s:debug "Http error: [string totitle [::http::status $token]] \( $url \)"
      http::cleanup $token
      return 0
   }
   if {[string match "*[http::ncode $token]*" "303|302|301" ]} {
      upvar #0 $token state
      foreach {name value} $state(meta) {
         if {[regexp -nocase ^location$ $name]} {
            if {![string match "http*" $value]} {
               if {![string match "/" [string index $value 0]]} {
                  set value "[join [lrange [split $url "/"] 0 2] "/"]/$value"
               } else {
                  set value "[join [lrange [split $url "/"] 0 2] "/"]$value"
               }
            }
            s:wget $value
            return
         }
      }
   }
   if {[string match 4* [http::ncode $token]] || [string match 5* [http::ncode $token]]} {
      putserv "PRIVMSG $chan: Http resource is not available: [http::ncode $token] \( $url \)"
      s:debug "Http resource is not evailable: [http::ncode $token] \( $url \)"
      return 0
   }
    set data [http::data $token]
    http::cleanup $token
    return $data
}

bind pub - !bittrex bittrexprices
proc bittrexprices {nick uhand handle chan input} {
    if {[llength $input]==0} {
      putserv "PRIVMSG $chan :You must include a coin after !price"
    } else {
      set querybittrex "https://www.bittrex.com/api/v1.1/public/GetMarketSummary?market=btc-"
      for { set index 0 } { $index<[llength $input] } { incr index } {
        set querybittrex "$querybittrex[lindex $input $index]"
        if {$index<[llength $input]-1} then {
          set querybittrex "$querybittrex+"
      }       
    } 
  }

# Bitstamp
set bitstamphttp [s:wget https://www.bitstamp.net/api/ticker/ ]
set bitstamp [json::json2dict $bitstamphttp]
set btclast [dict get $bitstamp last]
# BTC-E
set btcehttp [s:wget https://btc-e.com/api/2/btc_usd/ticker ]
set btce [json::json2dict $btcehttp]
set btbtclast [dict get [dict get $btce ticker] last]

# Bitstamp BTC-E Average
set usdavglast [expr {($btclast + $btbtclast) / 2}]

# Bittrex
set httpbittrex [::http::geturl $querybittrex]
set htmlbittrex [::http::data $httpbittrex]; ::http::cleanup $httpbittrex
regsub -all "\n" $htmlbittrex "" htmlbittrex
set bittrex [json::json2dict $htmlbittrex]
set bittrexname [dict get [lindex [dict get $bittrex result] 0] MarketName]
set bittrexlast [dict get [lindex [dict get $bittrex result] 0] Last]
set bittrexbid [dict get [lindex [dict get $bittrex result] 0] Bid]
set bittrexask [dict get [lindex [dict get $bittrex result] 0] Ask]
set bittrexlow [dict get [lindex [dict get $bittrex result] 0] Low]
set bittrexhigh [dict get [lindex [dict get $bittrex result] 0] High]
set bittrexvol [dict get [lindex [dict get $bittrex result] 0] Volume]
set bittrexbtcvol [dict get [lindex [dict get $bittrex result] 0] BaseVolume]
set bittrexprevday [dict get [lindex [dict get $bittrex result] 0] PrevDay]
set bittrexusdlast [format "%.4f" [expr {$bittrexlast * $usdavglast}]]
set bittrexusdbid [format "%.4f" [expr {$bittrexbid * $usdavglast}]]
set bittrexusdask [format "%.4f" [expr {$bittrexask * $usdavglast}]]
set bittrexusdlow [format "%.4f" [expr {$bittrexlow * $usdavglast}]]
set bittrexusdhigh [format "%.4f" [expr {$bittrexhigh * $usdavglast}]]
set bittrexvol [format "%.3f" $bittrexvol]
set bittrexbtcvol [format "%.3f" $bittrexbtcvol]

# % Change Maths
set 24change [format "%.2f" [expr {(($bittrexlast - $bittrexprevday)/$bittrexlast) * 100}]] 

# % Change Colors
proc color {change} {
   scan $change %g newnum
   if { $newnum < 0} {
    set color "\00304"
 } elseif { $newnum > 0} {
    set color "\00303"
 } else {
    set color "\003"
 }
   return $color
 }

# Output to channel
if {$bittrexname ne "null"} {
  # Bittrex
  set colorchange [color $24change]
  putnow "PRIVMSG $chan :\002$bittrexname\002 bittrex.com: \002Last:\002 $bittrexlast - \002Bid:\002 $bittrexbid - \002Ask:\002 $bittrexask - \002High:\002 $bittrexhigh - \002Low:\002 $bittrexlow // \002Vol:\002 $bittrexvol - \002VolBTC:\002 $bittrexbtcvol // \00224hr Change:\002$colorchange ${24change}%\003 // \002$bittrexname-USD\002 avg: \002Last:\002 $$bittrexusdlast - \002Bid:\002 $$bittrexusdbid - \002Ask:\002 $$bittrexusdask - \002High:\002 $$bittrexusdhigh - \002Low:\002 $$bittrexusdlow"
}
}
