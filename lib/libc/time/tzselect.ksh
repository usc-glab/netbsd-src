#! /bin/bash
#
# Ask the user about the time zone, and output the resulting TZ value to stdout.
# Interact with the user via stderr and stdin.
#
#	$NetBSD: tzselect.ksh,v 1.23 2024/02/17 14:54:47 christos Exp $
#
PKGVERSION='(tzcode) '
TZVERSION=see_Makefile
REPORT_BUGS_TO=tz@iana.org

# Contributed by Paul Eggert.  This file is in the public domain.

# Porting notes:
#
# This script requires a Posix-like shell and prefers the extension of a
# 'select' statement.  The 'select' statement was introduced in the
# Korn shell and is available in Bash and other shell implementations.
# If your host lacks both Bash and the Korn shell, you can get their
# source from one of these locations:
#
#	Bash <https://www.gnu.org/software/bash/>
#	Korn Shell <http://www.kornshell.com/>
#	MirBSD Korn Shell <http://www.mirbsd.org/mksh.htm>
#
# For portability to Solaris 10 /bin/sh (supported by Oracle through
# January 2024) this script avoids some POSIX features and common
# extensions, such as $(...) (which works sometimes but not others),
# $((...)), ! CMD, ${#ID}, ${ID##PAT}, ${ID%%PAT}, and $10.

#
# This script also uses several features of modern awk programs.
# If your host lacks awk, or has an old awk that does not conform to Posix,
# you can use either of the following free programs instead:
#
#	Gawk (GNU awk) <https://www.gnu.org/software/gawk/>
#	mawk <https://invisible-island.net/mawk/>
#	nawk <https://github.com/onetrueawk/awk>


# This script does not want path expansion.
set -f

# Specify default values for environment variables if they are unset.
: ${AWK=awk}
: ${PWD=`pwd`}
: ${TZDIR=$PWD}

# Output one argument as-is to standard output, with trailing newline.
# Safer than 'echo', which can mishandle '\' or leading '-'.
say() {
    printf '%s\n' "$1"
}

# Check for awk Posix compliance.
($AWK -v x=y 'BEGIN { exit 123 }') </dev/null >/dev/null 2>&1
[ $? = 123 ] || {
	say >&2 "$0: Sorry, your '$AWK' program is not Posix compatible."
	exit 1
}

coord=
location_limit=10
zonetabtype=zone1970

usage="Usage: tzselect [--version] [--help] [-c COORD] [-n LIMIT]
Select a timezone interactively.

Options:

  -c COORD
    Instead of asking for continent and then country and then city,
    ask for selection from time zones whose largest cities
    are closest to the location with geographical coordinates COORD.
    COORD should use ISO 6709 notation, for example, '-c +4852+00220'
    for Paris (in degrees and minutes, North and East), or
    '-c -35-058' for Buenos Aires (in degrees, South and West).

  -n LIMIT
    Display at most LIMIT locations when -c is used (default $location_limit).

  --version
    Output version information.

  --help
    Output this help.

Report bugs to $REPORT_BUGS_TO."

# Ask the user to select from the function's arguments,
# and assign the selected argument to the variable 'select_result'.
# Exit on EOF or I/O error.  Use the shell's nicer 'select' builtin if
# available, falling back on a portable substitute otherwise.
if
  case $BASH_VERSION in
  ?*) : ;;
  '')
    # '; exit' should be redundant, but Dash doesn't properly fail without it.
    (eval 'set --; select x; do break; done; exit') </dev/null 2>/dev/null
  esac
then
  # Do this inside 'eval', as otherwise the shell might exit when parsing it
  # even though it is never executed.
  eval '
    doselect() {
      select select_result
      do
	case $select_result in
	"") echo >&2 "Please enter a number in range." ;;
	?*) break
	esac
      done || exit
    }
  '
else
  doselect() {
    # Field width of the prompt numbers.
    print_nargs_length="BEGIN {print length(\"$#\");}"
    select_width=`$AWK "$print_nargs_length"`

    select_i=

    while :
    do
      case $select_i in
      '')
	select_i=0
	for select_word
	do
	  select_i=`$AWK "BEGIN { print $select_i + 1 }"`
	  printf >&2 "%${select_width}d) %s\\n" $select_i "$select_word"
	done ;;
      *[!0-9]*)
	echo >&2 'Please enter a number in range.' ;;
      *)
	if test 1 -le $select_i && test $select_i -le $#; then
	  shift `$AWK "BEGIN { print $select_i - 1 }"`
	  select_result=$1
	  break
	fi
	echo >&2 'Please enter a number in range.'
      esac

      # Prompt and read input.
      printf >&2 %s "${PS3-#? }"
      read select_i || exit
    done
  }
fi

while getopts c:n:t:-: opt
do
    case $opt$OPTARG in
    c*)
	coord=$OPTARG ;;
    n*)
	location_limit=$OPTARG ;;
    t*) # Undocumented option, used for developer testing.
	zonetabtype=$OPTARG ;;
    -help)
	exec echo "$usage" ;;
    -version)
	exec echo "tzselect $PKGVERSION$TZVERSION" ;;
    -*)
	say >&2 "$0: -$opt$OPTARG: unknown option; try '$0 --help'"; exit 1 ;;
    *)
	say >&2 "$0: try '$0 --help'"; exit 1 ;;
    esac
done

shift `$AWK "BEGIN { print $OPTIND - 1 }"`
case $# in
0) ;;
*) say >&2 "$0: $1: unknown argument"; exit 1 ;;
esac

# Make sure the tables are readable.
TZ_COUNTRY_TABLE=$TZDIR/iso3166.tab
TZ_ZONE_TABLE=$TZDIR/$zonetabtype.tab
for f in $TZ_COUNTRY_TABLE $TZ_ZONE_TABLE
do
	<"$f" || {
		say >&2 "$0: time zone files are not set up correctly"
		exit 1
	}
done

# If the current locale does not support UTF-8, convert data to current
# locale's format if possible, as the shell aligns columns better that way.
# Check the UTF-8 of U+12345 CUNEIFORM SIGN URU TIMES KI.
$AWK 'BEGIN { u12345 = "\360\222\215\205"; exit length(u12345) != 1 }' || {
    { tmp=`(mktemp -d) 2>/dev/null` || {
	tmp=${TMPDIR-/tmp}/tzselect.$$ &&
	(umask 77 && mkdir -- "$tmp")
    };} &&
    trap 'status=$?; rm -fr -- "$tmp"; exit $status' 0 HUP INT PIPE TERM &&
    (iconv -f UTF-8 -t //TRANSLIT <"$TZ_COUNTRY_TABLE" >$tmp/iso3166.tab) \
        2>/dev/null &&
    TZ_COUNTRY_TABLE=$tmp/iso3166.tab &&
    iconv -f UTF-8 -t //TRANSLIT <"$TZ_ZONE_TABLE" >$tmp/$zonetabtype.tab &&
    TZ_ZONE_TABLE=$tmp/$zonetabtype.tab
}

newline='
'
IFS=$newline

# Awk script to output a country list.
output_country_list='
  BEGIN { FS = "\t" }
  /^#$/ { next }
  /^#[^@]/ { next }
  {
    commentary = $0 ~ /^#@/
    if (commentary) {
      col1ccs = substr($1, 3)
      conts = $2
    } else {
      col1ccs = $1
      conts = $3
    }
    ncc = split(col1ccs, cc, /,/)
    ncont = split(conts, cont, /,/)
    for (i = 1; i <= ncc; i++) {
      elsewhere = commentary
      for (ci = 1; ci <= ncont; ci++) {
	if (cont[ci] ~ continent_re) {
	  if (!cc_seen[cc[i]]++) cc_list[++ccs] = cc[i]
	  elsewhere = 0
	}
      }
      if (elsewhere) {
	for (i = 1; i <= ncc; i++) {
	  cc_elsewhere[cc[i]] = 1
	}
      }
    }
  }
  END {
	  while (getline <TZ_COUNTRY_TABLE) {
		  if ($0 !~ /^#/) cc_name[$1] = $2
	  }
	  for (i = 1; i <= ccs; i++) {
		  country = cc_list[i]
		  if (cc_elsewhere[country]) continue
		  if (cc_name[country]) {
		    country = cc_name[country]
		  }
		  print country
	  }
  }
'

# Awk script to read a time zone table and output the same table,
# with each row preceded by its distance from 'here'.
# If output_times is set, each row is instead preceded by its local time
# and any apostrophes are escaped for the shell.
output_distances_or_times='
  BEGIN {
    FS = "\t"
    if (!output_times) {
      while (getline <TZ_COUNTRY_TABLE)
	if ($0 ~ /^[^#]/)
	  country[$1] = $2
      country["US"] = "US" # Otherwise the strings get too long.
    }
  }
  function abs(x) {
    return x < 0 ? -x : x;
  }
  function min(x, y) {
    return x < y ? x : y;
  }
  function convert_coord(coord, deg, minute, ilen, sign, sec) {
    if (coord ~ /^[-+]?[0-9]?[0-9][0-9][0-9][0-9][0-9][0-9]([^0-9]|$)/) {
      degminsec = coord
      intdeg = degminsec < 0 ? -int(-degminsec / 10000) : int(degminsec / 10000)
      minsec = degminsec - intdeg * 10000
      intmin = minsec < 0 ? -int(-minsec / 100) : int(minsec / 100)
      sec = minsec - intmin * 100
      deg = (intdeg * 3600 + intmin * 60 + sec) / 3600
    } else if (coord ~ /^[-+]?[0-9]?[0-9][0-9][0-9][0-9]([^0-9]|$)/) {
      degmin = coord
      intdeg = degmin < 0 ? -int(-degmin / 100) : int(degmin / 100)
      minute = degmin - intdeg * 100
      deg = (intdeg * 60 + minute) / 60
    } else
      deg = coord
    return deg * 0.017453292519943296
  }
  function convert_latitude(coord) {
    match(coord, /..*[-+]/)
    return convert_coord(substr(coord, 1, RLENGTH - 1))
  }
  function convert_longitude(coord) {
    match(coord, /..*[-+]/)
    return convert_coord(substr(coord, RLENGTH))
  }
  # Great-circle distance between points with given latitude and longitude.
  # Inputs and output are in radians.  This uses the great-circle special
  # case of the Vicenty formula for distances on ellipsoids.
  function gcdist(lat1, long1, lat2, long2, dlong, x, y, num, denom) {
    dlong = long2 - long1
    x = cos(lat2) * sin(dlong)
    y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlong)
    num = sqrt(x * x + y * y)
    denom = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(dlong)
    return atan2(num, denom)
  }
  # Parallel distance between points with given latitude and longitude.
  # This is the product of the longitude difference and the cosine
  # of the latitude of the point that is further from the equator.
  # I.e., it considers longitudes to be further apart if they are
  # nearer the equator.
  function pardist(lat1, long1, lat2, long2) {
    return abs(long1 - long2) * min(cos(lat1), cos(lat2))
  }
  # The distance function is the sum of the great-circle distance and
  # the parallel distance.  It could be weighted.
  function dist(lat1, long1, lat2, long2) {
    return gcdist(lat1, long1, lat2, long2) + pardist(lat1, long1, lat2, long2)
  }
  BEGIN {
    coord_lat = convert_latitude(coord)
    coord_long = convert_longitude(coord)
  }
  /^[^#]/ {
    inline[inlines++] = $0
    ncc = split($1, cc, /,/)
    for (i = 1; i <= ncc; i++)
      cc_used[cc[i]]++
  }
  END {
   for (h = 0; h < inlines; h++) {
    $0 = inline[h]
    line = $1 "\t" $2 "\t" $3
    sep = "\t"
    ncc = split($1, cc, /,/)
    split("", item_seen)
    item_seen[""] = 1
    for (i = 1; i <= ncc; i++) {
      item = cc_used[cc[i]] <= 1 ? country[cc[i]] : $4
      if (item_seen[item]++) continue
      line = line sep item
      sep = "; "
    }
    if (output_times) {
      fmt = "TZ='\''%s'\'' date +'\''%d %%Y %%m %%d %%H:%%M %%a %%b\t%s'\''\n"
      gsub(/'\''/, "&\\\\&&", line)
      printf fmt, $3, h, line
    } else {
      here_lat = convert_latitude($2)
      here_long = convert_longitude($2)
      printf "%g\t%s\n", dist(coord_lat, coord_long, here_lat, here_long), line
    }
   }
  }
'

# Begin the main loop.  We come back here if the user wants to retry.
while

	echo >&2 'Please identify a location' \
		'so that time zone rules can be set correctly.'

	continent=
	country=
	region=

	case $coord in
	?*)
		continent=coord;;
	'')

	# Ask the user for continent or ocean.

	echo >&2 'Please select a continent, ocean, "coord", "TZ", or "time".'

        quoted_continents=`
	  $AWK '
	    function handle_entry(entry) {
	      entry = substr(entry, 1, index(entry, "/") - 1)
	      if (entry == "America")
	       entry = entry "s"
	      if (entry ~ /^(Arctic|Atlantic|Indian|Pacific)$/)
	       entry = entry " Ocean"
	      printf "'\''%s'\''\n", entry
	    }
	    BEGIN { FS = "\t" }
	    /^[^#]/ {
              handle_entry($3)
            }
	    /^#@/ {
	      ncont = split($2, cont, /,/)
	      for (ci = 1; ci <= ncont; ci++) {
	        handle_entry(cont[ci])
	      }
	    }
          ' <"$TZ_ZONE_TABLE" |
	  sort -u |
	  tr '\n' ' '
	  echo ''
	`

	eval '
	    doselect '"$quoted_continents"' \
		"coord - I want to use geographical coordinates." \
		"TZ - I want to specify the timezone using a POSIX.1-2017 TZ string." \
		"time - I know local time already."
	    continent=$select_result
	    case $continent in
	    Americas) continent=America;;
	    *)
		# Get the first word of $continent.  Path expansion is disabled
		# so this works even with "*", which should not happen.
		IFS=" "
		for continent in $continent ""; do break; done
		IFS=$newline;;
	    esac
	'
	esac

	case $continent in
	TZ)
		# Ask the user for a POSIX.1-2017 TZ string.  Check that it conforms.
		while
			echo >&2 'Please enter the desired value' \
				'of the TZ environment variable.'
			echo >&2 'For example, AEST-10 is abbreviated' \
				'AEST and is 10 hours'
			echo >&2 'ahead (east) of Greenwich,' \
				'with no daylight saving time.'
			read TZ
			$AWK -v TZ="$TZ" 'BEGIN {
				tzname = "(<[[:alnum:]+-]{3,}>|[[:alpha:]]{3,})"
				time = "(2[0-4]|[0-1]?[0-9])" \
				  "(:[0-5][0-9](:[0-5][0-9])?)?"
				offset = "[-+]?" time
				mdate = "M([1-9]|1[0-2])\\.[1-5]\\.[0-6]"
				jdate = "((J[1-9]|[0-9]|J?[1-9][0-9]" \
				  "|J?[1-2][0-9][0-9])|J?3[0-5][0-9]|J?36[0-5])"
				datetime = ",(" mdate "|" jdate ")(/" time ")?"
				tzpattern = "^(:.*|" tzname offset "(" tzname \
				  "(" offset ")?(" datetime datetime ")?)?)$"
				if (TZ ~ tzpattern) exit 1
				exit 0
			}'
		do
		    say >&2 "'$tz' is not a conforming POSIX.1-2017 timezone string."
		done
		TZ_for_date=$TZ;;
	*)
		case $continent in
		coord)
		    case $coord in
		    '')
			echo >&2 'Please enter coordinates' \
				'in ISO 6709 notation.'
			echo >&2 'For example, +4042-07403 stands for'
			echo >&2 '40 degrees 42 minutes north,' \
				'74 degrees 3 minutes west.'
			read coord;;
		    esac
		    distance_table=`$AWK \
			    -v coord="$coord" \
			    -v TZ_COUNTRY_TABLE="$TZ_COUNTRY_TABLE" \
			    "$output_distances_or_times" <"$TZ_ZONE_TABLE" |
		      sort -n |
		      $AWK "{print} NR == $location_limit { exit }"
		    `
		    regions=`$AWK \
		      -v distance_table="$distance_table" '
		      BEGIN {
		        nlines = split(distance_table, line, /\n/)
			for (nr = 1; nr <= nlines; nr++) {
			  nf = split(line[nr], f, /\t/)
			  print f[nf]
			}
		      }
		    '`
		    echo >&2 'Please select one of the following timezones,'
		    echo >&2 'listed roughly in increasing order' \
			    "of distance from $coord".
		    doselect $regions
		    region=$select_result
		    TZ=`$AWK \
		      -v distance_table="$distance_table" \
		      -v region="$region" '
		      BEGIN {
		        nlines = split(distance_table, line, /\n/)
			for (nr = 1; nr <= nlines; nr++) {
			  nf = split(line[nr], f, /\t/)
			  if (f[nf] == region) {
			    print f[4]
			  }
			}
		      }
		    '`
		    ;;
		*)
		case $continent in
		time)
		  minute_format='%a %b %d %H:%M'
		  old_minute=`TZ=UTC0 date +"$minute_format"`
		  for i in 1 2 3
		  do
		    time_table_command=`
		      $AWK -v output_times=1 \
			  "$output_distances_or_times" <"$TZ_ZONE_TABLE"
		    `
		    time_table=`eval "$time_table_command"`
		    new_minute=`TZ=UTC0 date +"$minute_format"`
		    case $old_minute in
		    "$new_minute") break;;
		    esac
		    old_minute=$new_minute
		  done
		  echo >&2 "The system says Universal Time is $new_minute."
		  echo >&2 "Assuming that's correct, what is the local time?"
		  eval doselect `
		    say "$time_table" |
		    sort -k2n -k2,5 -k1n |
		    $AWK '{
		      line = $6 " " $7 " " $4 " " $5
		      if (line == oldline) next
		      oldline = line
		      gsub(/'\''/, "&\\\\&&", line)
		      printf "'\''%s'\''\n", line
		    }'
		  `
		  time=$select_result
		  zone_table=`
		    say "$time_table" |
		    $AWK -v time="$time" '{
		      if ($6 " " $7 " " $4 " " $5 == time) {
			sub(/[^\t]*\t/, "")
			print
		      }
		    }'
		  `
		  countries=`
		     say "$zone_table" |
		     $AWK \
			-v continent_re='' \
			-v TZ_COUNTRY_TABLE="$TZ_COUNTRY_TABLE" \
			"$output_country_list" |
		     sort -f
		  `
		  ;;
		*)
		  zone_table=file
		  # Get list of names of countries in the continent or ocean.
		  countries=`$AWK \
			-v continent_re="^$continent/" \
			-v TZ_COUNTRY_TABLE="$TZ_COUNTRY_TABLE" \
			"$output_country_list" \
			<"$TZ_ZONE_TABLE" | sort -f
		  `;;
		esac

		# If there's more than one country, ask the user which one.
		case $countries in
		*"$newline"*)
			echo >&2 'Please select a country' \
				'whose clocks agree with yours.'
			doselect $countries
			country_result=$select_result
			country=$select_result;;
		*)
			country=$countries
		esac


		# Get list of timezones in the country.
		regions=`
		  case $zone_table in
		  file) cat -- "$TZ_ZONE_TABLE";;
		  *) say "$zone_table";;
		  esac |
		  $AWK \
			-v country="$country" \
			-v TZ_COUNTRY_TABLE="$TZ_COUNTRY_TABLE" \
		    '
			BEGIN {
				FS = "\t"
				cc = country
				while (getline <TZ_COUNTRY_TABLE) {
					if ($0 !~ /^#/  &&  country == $2) {
						cc = $1
						break
					}
				}
			}
			/^#/ { next }
			$1 ~ cc { print $4 }
		    '
		`


		# If there's more than one region, ask the user which one.
		case $regions in
		*"$newline"*)
			echo >&2 'Please select one of the following timezones.'
			doselect $regions
			region=$select_result
		esac

		# Determine TZ from country and region.
		TZ=`
		  case $zone_table in
		  file) cat -- "$TZ_ZONE_TABLE";;
		  *) say "$zone_table";;
		  esac |
		  $AWK \
			-v country="$country" \
			-v region="$region" \
			-v TZ_COUNTRY_TABLE="$TZ_COUNTRY_TABLE" \
		    '
			BEGIN {
				FS = "\t"
				cc = country
				while (getline <TZ_COUNTRY_TABLE) {
					if ($0 !~ /^#/  &&  country == $2) {
						cc = $1
						break
					}
				}
			}
			/^#/ { next }
			$1 ~ cc && ($4 == region || !region) { print $3 }
		    '
		`;;
		esac

		# Make sure the corresponding zoneinfo file exists.
		TZ_for_date=$TZDIR/$TZ
		<"$TZ_for_date" || {
			say >&2 "$0: time zone files are not set up correctly"
			exit 1
		}
	esac


	# Use the proposed TZ to output the current date relative to UTC.
	# Loop until they agree in seconds.
	# Give up after 8 unsuccessful tries.

	extra_info=
	for i in 1 2 3 4 5 6 7 8
	do
		TZdate=`LANG=C TZ="$TZ_for_date" date`
		UTdate=`LANG=C TZ=UTC0 date`
		if $AWK '
		      function getsecs(d) {
			return match(d, /.*:[0-5][0-9]/) ? substr(d, RLENGTH - 1, 2) : ""
		      }
		      BEGIN { exit getsecs(ARGV[1]) != getsecs(ARGV[2]) }
		   ' ="$TZdate" ="$UTdate"
		then
			extra_info="
Selected time is now:	$TZdate.
Universal Time is now:	$UTdate."
			break
		fi
	done


	# Output TZ info and ask the user to confirm.

	echo >&2 ""
	echo >&2 "Based on the following information:"
	echo >&2 ""
	case $time%$country_result%$region%$coord in
	?*%?*%?*%)
	  say >&2 "	$time$newline	$country_result$newline	$region";;
	?*%?*%%|?*%%?*%) say >&2 "	$time$newline	$country_result$region";;
	?*%%%) say >&2 "	$time";;
	%?*%?*%) say >&2 "	$country_result$newline	$region";;
	%?*%%)	say >&2 "	$country_result";;
	%%?*%?*) say >&2 "	coord $coord$newline	$region";;
	%%%?*)	say >&2 "	coord $coord";;
	*)	say >&2 "	TZ='$TZ'"
	esac
	say >&2 ""
	say >&2 "TZ='$TZ' will be used.$extra_info"
	say >&2 "Is the above information OK?"

	doselect Yes No
	ok=$select_result
	case $ok in
	Yes) break
	esac
do coord=
done

case $SHELL in
*csh) file=.login line="setenv TZ '$TZ'";;
*) file=.profile line="TZ='$TZ'; export TZ"
esac

test -t 1 && say >&2 "
You can make this change permanent for yourself by appending the line
	$line
to the file '$file' in your home directory; then log out and log in again.

Here is that TZ value again, this time on standard output so that you
can use the $0 command in shell scripts:"

say "$TZ"
