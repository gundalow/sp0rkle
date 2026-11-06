#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <unistd.h>

extern int irc_console_run(const char *, const char *, const char *, const char *);

struct server_state { int listener; int port; int failed; };

static int read_line(int fd, char *out, size_t cap) {
    size_t n=0;
    while(n+1<cap) {
        char ch;
        ssize_t r=recv(fd,&ch,1,0);
        if(r<=0) return -1;
        out[n++]=ch;
        if(ch=='\n') { out[n]=0; return (int)n; }
    }
    return -1;
}
static int send_all(int fd,const char *s) {
    size_t n=strlen(s),off=0;
    while(off<n) { ssize_t r=send(fd,s+off,n-off,0); if(r<=0)return -1; off+=(size_t)r; }
    return 0;
}
static void *server_main(void *arg) {
    struct server_state *st=arg;
    int fd=accept(st->listener,NULL,NULL);
    if(fd<0){st->failed=1;return NULL;}
    char line[512];
    if(read_line(fd,line,sizeof(line))<0 || strncmp(line,"NICK testbot\r\n",14)) st->failed=1;
    if(read_line(fd,line,sizeof(line))<0 || strncmp(line,"USER testbot ",13)) st->failed=1;
    if(send_all(fd,":test.server 001 testbot :Welcome\r\n")) st->failed=1;
    if(read_line(fd,line,sizeof(line))<0 || strcmp(line,"JOIN #test\r\n")) st->failed=1;
    if(send_all(fd,"PING :probe\r\n:test.server NOTICE testbot :visible message\r\n")) st->failed=1;
    if(read_line(fd,line,sizeof(line))<0 || strcmp(line,"PONG :probe\r\n")) st->failed=1;
    close(fd);
    return NULL;
}

int main(void) {
    struct server_state st={0};
    st.listener=socket(AF_INET,SOCK_STREAM,0); assert(st.listener>=0);
    int yes=1; setsockopt(st.listener,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    struct sockaddr_in addr={0}; addr.sin_family=AF_INET; addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK); addr.sin_port=0;
    assert(bind(st.listener,(struct sockaddr *)&addr,sizeof(addr))==0);
    assert(listen(st.listener,1)==0);
    socklen_t alen=sizeof(addr); assert(getsockname(st.listener,(struct sockaddr *)&addr,&alen)==0);
    st.port=ntohs(addr.sin_port);
    pthread_t thread; assert(pthread_create(&thread,NULL,server_main,&st)==0);

    int output[2]; assert(pipe(output)==0);
    fflush(stdout); int saved=dup(STDOUT_FILENO); assert(saved>=0);
    assert(dup2(output[1],STDOUT_FILENO)>=0); close(output[1]);
    char port[16]; snprintf(port,sizeof(port),"%d",st.port);
    int rc=irc_console_run("127.0.0.1",port,"testbot","#test");
    fflush(stdout);
    assert(dup2(saved,STDOUT_FILENO)>=0); close(saved);
    char captured[2048]; ssize_t n=read(output[0],captured,sizeof(captured)-1); assert(n>=0); captured[n]=0; close(output[0]);
    pthread_join(thread,NULL); close(st.listener);
    assert(rc==0); assert(st.failed==0);
    assert(strstr(captured,"001 testbot :Welcome")!=NULL);
    assert(strstr(captured,"NOTICE testbot :visible message")!=NULL);
    puts("IRC console tests: PASS");
    return 0;
}
