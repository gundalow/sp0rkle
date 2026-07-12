package urldriver

import (
	"strings"
	"time"

	"github.com/fluffle/sp0rkle/bot"
	"github.com/fluffle/sp0rkle/collections/urls"
	"github.com/fluffle/sp0rkle/util"
)

func (d *Driver) urlScan(ctx *bot.Context) {
	words := strings.Split(ctx.Text(), " ")
	n, c := ctx.Storable()
	for _, w := range words {
		if util.LooksURLish(w) {
			if u := d.uc.GetByUrl(w); u.Exists() {
				if u.Nick != bot.Nick(ctx.Nick) &&
					time.Since(u.Timestamp) > 2*time.Hour {
					ctx.Reply("that URL first mentioned by %s %s ago",
						u.Nick, util.TimeSince(u.Timestamp))
				}
				continue
			}
			u := urls.NewUrl(w, n, c)
			if IsImgurURL(w) {
				u.Shortened = d.Encode(w)
				// d.Cache(u) downloads the image via proxy, generates CachedAs, and persists the
				// u object (with both Shortened and CachedAs) to the database via d.uc.Put(u).
				if err := d.Cache(u); err != nil {
					ctx.ReplyN("Failed to store cached url: %s", err)
					continue
				}
				if u.Shortened != "" {
					ctx.Reply("%s's URL shortened as %s%s%s",
						ctx.Nick, bot.HttpHost(), shortenPath, u.Shortened)
				}
				ctx.Reply("%s's URL cached as %s%s%s",
					ctx.Nick, bot.HttpHost(), cachePath, u.CachedAs)
				d.lastseen[ctx.Target()] = u.Id_
				continue
			}

			if len(w) > autoShortenLimit && ctx.Public() {
				u.Shortened = d.Encode(w)
			}
			if err := d.uc.Put(u); err != nil {
				ctx.ReplyN("Couldn't insert url '%s': %s", w, err)
				continue
			}
			if u.Shortened != "" {
				ctx.Reply("%s's URL shortened as %s%s%s",
					ctx.Nick, bot.HttpHost(), shortenPath, u.Shortened)
			}
			d.lastseen[ctx.Target()] = u.Id_
		}
	}
}
