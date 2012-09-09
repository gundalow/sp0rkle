package calcdriver

import (
	"fmt"
	"github.com/fluffle/goevent/event"
	"github.com/fluffle/sp0rkle/lib/calc"
	"github.com/fluffle/sp0rkle/sp0rkle/base"
	"github.com/fluffle/sp0rkle/sp0rkle/bot"
	"net"
	"strings"
	"strconv"
	"unicode/utf8"
)

func (cd *calcDriver) RegisterHandlers(r event.EventRegistry) {
	r.AddHandler(bot.NewHandler(cd_privmsg), "bot_privmsg")
}

func cd_privmsg(bot *bot.Sp0rkle, line *base.Line) {
	if !line.Addressed {
		return
	}

	switch {
	case strings.HasPrefix(line.Args[1], "calc "):
		cd_calc(bot, line, line.Args[1][5:])
	case strings.HasPrefix(line.Args[1], "netmask "):
		s := strings.Split(line.Args[1], " ")
		if strings.Index(s[1], "/") != -1 {
			// Assume we have netmask ip/cidr
			cd_netmask_cidr(bot, line, s[1])
		} else if len(s) == 3 {
			// Assume we have netmask ip nm
			cd_netmask(bot, line, s[1], s[2])
		}
	case strings.HasPrefix(line.Args[1], "chr "):
		cd_chr(bot, line, line.Args[1][4:])
	case strings.HasPrefix(line.Args[1], "ord "):
		cd_ord(bot, line, line.Args[1][4:])
	case strings.HasPrefix(line.Args[1], "length "):
		bot.ReplyN(line, "'%s' is %d characters long",
			line.Args[1][7:], len(line.Args[1][7:]))
	case strings.HasPrefix(line.Args[1], "base "):
		s := strings.Split(line.Args[1], " ")
		cd_base(bot, line, s[1], s[2])
	}
}

func cd_calc(bot *bot.Sp0rkle, line *base.Line, maths string) {
	if num, err := calc.Calc(maths); err == nil {
		bot.ReplyN(line, "%s = %g", maths, num)
	} else {
		bot.ReplyN(line, "%s error while parsing %s", err, maths)
	}
}

func cd_netmask_range(ip net.IP, mask net.IPMask) (btm, top net.IP) {
	btm = ip.Mask(mask)
	top = make(net.IP, len(ip))
	copy(top, ip)
	for i, b := range mask {
		top[i] |= ^b
	}
	return
}

func cd_netmask_cidr(bot *bot.Sp0rkle, line *base.Line, cidr string) {
	if _, nm, err := net.ParseCIDR(cidr); err == nil {
		btm, top := cd_netmask_range(nm.IP, nm.Mask)
		bot.ReplyN(line, "%s is in the range %s-%s and has the netmask %s",
			cidr, btm, top, net.IP(nm.Mask))
	} else {
		bot.ReplyN(line, "error parsing ip/cidr %s: %s", cidr, err)
	}
}

func cd_netmask(bot *bot.Sp0rkle, line *base.Line, ips, nms string) {
	ip := net.ParseIP(ips)
	nmip := net.ParseIP(nms)
	if ip == nil || nmip == nil {
		bot.ReplyN(line, "either %s or %s couldn't be parsed as an IP", ips, nms)
		return
	}
	// this is a bit of a hack, because using ParseIP to parse
	// something that's actually a v4 netmask doesn't quite work
	nm := net.IPMask(nmip.To4())
	cidr, bits := nm.Size()
	if ip.To4() != nil && nm != nil {
		if bits != 32 {
			bot.ReplyN(line, "%s doesn't look like a valid IPv4 netmask", nms)
			return
		}
	} else {
		// IPv6, hopefully
		nm = net.IPMask(nmip)
		cidr, bits = nm.Size()
		if bits != 128 {
			bot.ReplyN(line, "%s doesn't look like a valid IPv6 netmask", nms)
			return
		}
	}
	btm, top := cd_netmask_range(ip, nm)
	bot.ReplyN(line, "%s/%d is in the range %s-%s and has the netmask %s",
		ip, cidr, btm, top, nmip)
}

func cd_chr(bot *bot.Sp0rkle, line *base.Line, chr string) {
	// handles decimal, hex, and octal \o/
	i, err := strconv.ParseInt(chr, 0, 0)
	if err != nil {
		bot.ReplyN(line, "Couldn't parse %s as an integer: %s", chr, err)
		return
	}
	bot.ReplyN(line, "chr(%s) is %c, %U, '%s'", chr, i, i, cd_utf8repr(rune(i)))
}

func cd_ord(bot *bot.Sp0rkle, line *base.Line, ord string) {
	r, _ := utf8.DecodeRuneInString(ord)
	if r == utf8.RuneError {
		bot.ReplyN(line, "Couldn't parse a utf8 rune from %s", ord)
		return
	}
	bot.ReplyN(line, "ord(%c) is %d, %U, '%s'", r, r, r, cd_utf8repr(r))
}

func cd_utf8repr(r rune) string {
	p := make([]byte, 4)
	n := utf8.EncodeRune(p, r)
	s := make([]string, n)
	for i, c := range p[:n] {
		s[i] = fmt.Sprintf("0x%x", c)
	}
	return strings.Join(s, " ")
}

func cd_base(bot *bot.Sp0rkle, line *base.Line, base, num string) {
	fromto := strings.Split(base, "to")
	if len(fromto) != 2 {
		bot.ReplyN(line, "Specify base as: <from base>to<to base>")
		return
	}
	from, errf := strconv.Atoi(fromto[0])
	to, errt := strconv.Atoi(fromto[1])
	if errf != nil || errt != nil ||
		from < 2 || from > 36 || to < 2 || to > 36 {
		bot.ReplyN(line, "Either %s or %s is a bad base, must be in range 2-36",
			fromto[0], fromto[1])
		return
	}
	i, err := strconv.ParseInt(num, from, 64)
	if err != nil {
		bot.ReplyN(line, "Couldn't parse %s as a base %d integer", num, from)
		return
	}
	bot.ReplyN(line, "%s in base %d is %s in base %d",
		num, from, strconv.FormatInt(i, to), to)
}
