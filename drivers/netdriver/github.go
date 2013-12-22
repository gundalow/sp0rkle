package netdriver

import (
	"code.google.com/p/goauth2/oauth"
	"flag"
	"fmt"
	"github.com/google/go-github/github"
	"github.com/fluffle/golog/logging"
	"github.com/fluffle/sp0rkle/bot"
	"github.com/fluffle/sp0rkle/collections/reminders"
	"strings"
	"time"
)

var (
	githubToken = flag.String("github_token", "",
		"OAuth2 token for accessing the GitHub API.")
	githubPollFreq = flag.Duration("github_poll_freq", 4 * time.Hour,
		"Frequency to poll github for bug updates.")
)

const (
	githubUser = "fluffle"
	githubRepo = "sp0rkle"
	githubURL = "https://github.com/"+githubUser+"/"+githubRepo
	githubIssuesURL = githubURL + "/issues"
	ISO8601 = "2006-01-02T15:04:05Z"
	timeFormat = "15:04:05, Monday 2 January 2006"
)

func sp(s string) *string {
	//  FFFUUUUuuu string pointers in Issue literals.
	return &s
}

func githubClient() *github.Client {
	t := &oauth.Transport{Token: &oauth.Token{AccessToken: *githubToken}}
	return github.NewClient(t.Client())
}

func githubCreateIssue(ctx *bot.Context, gh *github.Client) {
	s := strings.SplitN(ctx.Text(), ". ", 2)
	if s[0] == "" {
		ctx.ReplyN("I'm not going to create an empty issue.")
		return
	}

	issue := &github.Issue{
		Title:    sp(s[0] + "."),
	}
	if len(s) == 2 {
		issue.Body = &s[1]
	}
	issue, _, err := gh.Issues.Create(githubUser, githubRepo, issue)
	if err != nil {
		ctx.ReplyN("Error creating issue: %v", err)
		return
	}
	// Can't set labels on create due to go-github #75 :/
	_, _, err = gh.Issues.ReplaceLabelsForIssue(
		githubUser, githubRepo, *issue.Number,
		[]string{"from:IRC", "nick:"+ctx.Nick, "chan:"+ctx.Target()})
	if err != nil {
		ctx.ReplyN("Failed to add labels to issue: %v", err)
	}
	ctx.ReplyN("Issue #%d created at %s/%d",
		*issue.Number, githubIssuesURL, *issue.Number)
}

type ghPoller struct {
	// essentially a github client.
	*github.Client
}

type ghUpdate struct {
	issue                int
	updated, closed      time.Time
	nick, channel, title string
	comment, commenter   string
}

func (u ghUpdate) String() string {
	s := []string{fmt.Sprintf("that issue %s/%d (%s)",
		githubIssuesURL, u.issue, u.title)}
	if !u.closed.IsZero() {
		s = append(s, fmt.Sprintf("was closed at %s.",
			u.closed.Format(timeFormat)))
	} else {
		s = append(s, fmt.Sprintf("was updated at %s.",
			u.updated.Format(timeFormat)))
	}
	if u.comment != "" {
		comment := u.comment
		trunc := " "
		if len(comment) > 100 {
			idx := strings.Index(comment, " ") + 100
			if idx >= 100 {
				comment = comment[:idx] + "..."
				trunc = " (truncated) "
			}
		}
		s = append(s, fmt.Sprintf("Recent%scomment by %s: '%s'",
			trunc, u.commenter, comment))
	}
	return strings.Join(s, " ")
}

func githubPoller(gh *github.Client) *ghPoller {
	return &ghPoller{gh}
}

func (ghp *ghPoller) Poll([]*bot.Context) { ghp.getIssues() }
func (ghp *ghPoller) Start() { /* empty */ }
func (ghp *ghPoller) Stop() { /* empty */ }
func (ghp *ghPoller) Tick() time.Duration { return *githubPollFreq }

func (ghp *ghPoller) getIssues() {
	opts := &github.IssueListByRepoOptions{
		Labels: []string{"from:IRC"},
		Sort:   "updated",
		State:  "open",
		Since:  time.Now().Add(*githubPollFreq * -1),
	}
	open, _, err := ghp.Issues.ListByRepo("fluffle", "sp0rkle", opts)
	if err != nil {
		logging.Error("Error listing open issues: %v", err)
	}
	opts.State = "closed"
	closed, _, err := ghp.Issues.ListByRepo("fluffle", "sp0rkle", opts)
	if err != nil {
		logging.Error("Error listing open issues: %v", err)
	}
	open = append(open, closed...)
	logging.Debug("Polling github for issues: %d issues found.", len(open))
	if len(open) == 0 { return }
	for _, issue := range open {
		update := ghp.parseIssue(issue)
		logging.Info("Adding tell for %s regarding issue %d.", update.nick, update.issue)
		r := reminders.NewTell(update.String(), bot.Nick(update.nick),
			"github", bot.Chan(update.channel))
		if err := rc.Insert(r); err != nil {
			logging.Error("Error inserting github tell: %v", err)
		}
	}
}

func (ghp *ghPoller) parseIssue(issue github.Issue) ghUpdate {
	update := ghUpdate{
		issue:   *issue.Number,
		updated: *issue.UpdatedAt,
		title:   *issue.Title,
	}
	if issue.ClosedAt != nil && time.Now().Sub(*issue.ClosedAt) < *githubPollFreq {
		update.closed = *issue.ClosedAt
	}
	for _, l := range issue.Labels {
		kv := strings.Split(*l.Name, ":")
		if len(kv) != 2 {
			continue
		}
		switch kv[0] {
		case "nick":
			update.nick = kv[1]
		case "chan":
			update.channel = kv[1]
		}
	}
	if *issue.Comments == 0 { return update }
	opts := &github.IssueListCommentsOptions{
		Sort: "updated",
		Direction: "desc",
		Since:  time.Now().Add(*githubPollFreq * -1),
	}
	comm, _ , err := ghp.Issues.ListComments(
		"fluffle", "sp0rkle", *issue.Number, opts)
	if err != nil {
		logging.Error("Error getting comments for issue %d: %v",
			*issue.Number, err)
	} else {
		update.comment = *comm[0].Body
		update.commenter = *comm[0].User.Login
	}
	return update
}
