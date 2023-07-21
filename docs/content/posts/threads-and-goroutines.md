+++
title = "Threads and Goroutines"
date = "2023-06-12T15:33:25-07:00"
author = "Shane Hansen"
authorTwitter = "" #do not include @
cover = ""
tags = ["", ""]
keywords = ["", ""]
description = ""
showFullContent = false
readingTime = false
hideComments = false
color = "" #color from the theme settings
+++

So after several years of reading oversimplified and flat out incorrect comments about threads and fibers/goroutines/async/etc and fighting this reaction:

![Someone on the internet is wrong](https://imgs.xkcd.com/comics/duty_calls.png)

I've decided to write my own still-over-simplified all in one guide to the difference between a couple popular threads and fiber implementations. In order to keep this a blog post
and not a novel I'm just going to focus on linux threads, go goroutines, and rust threads.

tl;dr - Rust threads on linux use 8kb of memory, Goroutuines use 2kb. It's a big difference but nowhere near as big as the "kilobytes vs megabytes" claim I often see repeated.

I'd like to give you better tools to reason about systems engineering questions like "should we use one thread per client?" "do we need to be async to scale?" "what concurrency architecture should I choose for my next project?"

Let's start with an example because the rest of the article will essentially discuss these results. We'll talk about whether or not they are surprising and the tradeoffs necessary to get them. So the first question is:

## How heavy are threads?

I first want to look at how much memory a thread uses. You can find this out simply enough on linux via `ulimit` It's changeable. Run this on your favorite linux machine to see what you get. As you can see I get 8 megabytes.

```sh
$ ulimit -a | grep stack
stack size                  (kbytes, -s) 8192
```

Now this number is correct, but it's often misinterpreted. Now you might think that to make a new thread I need 8 megabytes of RAM free. But thanks to the magic of virtual memory and overcommit, that's not necessarily the case.
The right way to think about this is that the OS, let's assume 64bit, is going to allocate you your own private range but this doesn't really have to be backed by anything. There are alot of 8mb blocks in a 64bit address space.
However there is some book keeping overhead as the kernel tracks it's IOUs.

Let's write a trivialish program in rust to allocate a million threads and measure the resident memory. But before we do that,
you might have to bump up a couple limits on your system to get the program to run. Here's whad I had to do:

```sh
sysctl -w vm.max_map_count=4000000
sysctl -w kernel.threads-max=2000000000
```

Threads-max is self explanatory, but while I didn't do much deep digging I'm guessing max_map_count literally refers to memory regions allocated as stacks. So more threads = more stacks = more memory maps.

Finally I wrote this simple rust program to allocate a million threads that sleep for 1 second, and then wait for all of them. I haven't published the repo yet
but if you can run `cargo new --bin` and drop this in `main.rs` you should be able to build/run.

```rust
use std::thread;
use std::time::Duration;

fn main() {
    let count = 1_000_000;
    let mut handles = Vec::with_capacity(count);
    for _ in 1..count {
	handles.push(thread::spawn(|| {
	    thread::sleep(Duration::from_millis(1000));
        }));
    }
    for handle in handles {
	handle.join().unwrap();
    }
}
```

Let's run it and see how it performs:

```sh
cargo build --release
/usr/bin/time ./target/release/threads
6.17user 80.41system 0:38.55elapsed 224%CPU (0avgtext+0avgdata 8500640maxresident)k
0inputs+0outputs (0major+2125114minor)pagefaults 0swaps
```

So for those aren't used to reading the somewhat cryptic output of /usr/bin/time, here's how to look at it:

1. 6s of user time: so all the rust code creating/sleeping/etc took 6s.
2. 80s system time over 38s elapsed time. Which basically says we kept 2 cores busy for 38s and much of the work was in the kernel.
3. 8500640maxresidentk -> 8.5GB of RAM actually used. Divide that by a million threads and you get about 8KB overhead per thread/stack. That's not too shabby for a "heavyweight" thread.

Virtual memory (as scientifically observed by watching `top`) peaked at just under 2TB, so about 2MB per thread. How does that square with the 8MB value I said before? I don't know. Maybe rust
passes some flags into `clone()` to override the default.

But there you have it: ignoring kernel structure tracking overhead, simple OS threads that don't do much work use just 8KB of actual RAM on my system. What about Go?

## Goroutines and stuff

Quick disclaimer: dear pedants: I'm aware that a language and a particular implementation are different things and what I'm about to say doesn't apply to gccgo. For the rest of this article
"Go" is both the Go programming language as well as the official Go toolchain.

With that out of the way: what are goroutines, how do they differ from threads, and how does that make them better or worse?

From a programmer point of view, a goroutine is basically a thread. It's a function that runs concurrently (and potentially in parallel) with the rest of your program. Executing a function in
a goroutine can allow you to utilize more CPU cores. Go has a M:N threading model which means all your M goroutines are multiplexed over all your N threads (which are then multiplexed over all your CPUs by the kernel). Go defaults to NumThreads==NumCores,
even if you have a million goroutines. With threads you rely on the operating system to switch from one task to another. In Go some of that work happens in userspace. I'll talk more about the details of the differences but first: let's run a the
same "one million tasks sleeping for one second" test:


```go
package main
import (
	"time"
	"sync"
)
func main() {
    var wg sync.WaitGroup
    count := 1000000
    wg.Add(count)
    for i:=0;i<count;i++ {
	   go func() {
		   defer wg.Done()
		   time.Sleep(time.Second)
	   }()
    }
	wg.Wait()
}
```

Let's build it

```sh
go build -o threads main.go
/usr/bin/time ./threads 
16.66user 0.68system 0:02.44elapsed 709%CPU (0avgtext+0avgdata 2122296maxresident)k
0inputs+0outputs (0major+529900minor)pagefaults 0swaps
```

So right off the bat we see:

1. 16s user time. That's way more than rust. Because the rust example is just a shim making syscalls and go is performing scheduling work in userspace.
2. 0.68 system time. That's low.
3. 2_122_296maxresident)k. 2 gigabytes of RAM resident or just 2KB/goroutine!
4. My unscientific measurement of virtual memory also reported 2GB.

In this simple benchmark go is over 10x faster at creating a million threads that do some light scheduling. Memory usage is different, but generally same
order of magnitude. It would be a reasonable assumption to say that a non-trivial program would likely exceed 2KB stack starting size and cause it to grow (that's a thing go can do) and so the real memory
usage of rust & go could converge pretty quickly.

Putting on my practical hat right now: if someone told me they wanted to run a service with a million goroutines I'd be a little nervous. If they told me they needed to run a service with
a million threads I'd be more nervous because of virtual memory overhead and managing sysctls. But today's hardware is up for the challenge.

So if that's true what's the value of goroutines? I like saving RAM and 2GB is smaller than 8GB, but frankly if I'm changing runtimes and languages for better performance I want closer to 10x real world
improvement.

I get asked this question all the time while teaching classes. If goroutines are so cheap why can't the kernel just make structures that cheap? If go can get away with small stacks why can't the kernel? Go's
task switching was initially "cooperative" (technically cooperative but managed by the runtime/compiler not the user) and now it's "preemptive" so it seems like go has to do basically the same context
switching for goroutines that the kernel does for threads: namely saving/restoring registers.

I'll be honest: I don't entirely know the answer but it comes down to the actual implementation details. Go can get away with allocating smaller stacks because go has always been able to grow the stack if needed. This
is a capability that is tied to the runtime. Regular programs using the Thread api (or clone or libc wrappers) may not have always been able to count on growable stacks. Because go has a more tightly integrated userspace
scheduler and concurrency primitives sometimes it can context switch with less overhead. For example if one goroutine is writing to a channel and one goroutine is reading to a channel, it's possible go can literally run
the reader and the writer on the same thread and take a fast path where the writer goroutine calls send and that triggers the current thread to switchto the reader goroutine.

I also suspect (but have no proof) that the go compiler may be able to be less conservative about register state it saves/restores. The linux kernel has to be potentially be ready for more hostile user code. In practice I think
there might be some ancient legacy registers/flags that the kernel has to handle that the go compiler doesn't.

So far I've made goroutines sound pretty boring. They are like threads but use same order of magnitude of RAM. They occasionally can be scheduled smartly but I haven't presented any evidence they can be scheduled/context switched
more efficiently than regular threads. The biggest real benefit I see is that I can use lots of goroutines without worrying as much about configuring system resources.

So why do they exist and why are they awesome? The answer is actually simple, but first we have to talk about async I/O. The most scalable network I/O on linux is an asynchronous interface called `epoll`. Another feature called `io_uring` is shaping up to be the most scalable syscall mechanism on linux but it's hoped Go can just switch to that when the time comes. Because these interfaces are async you don't really block a thread on a  `.Read()` call. Typically we call these systems event driven and utilize `callbacks`, short handler functions, to react to new data being read. Node.js for example uses libuv under the hood to do efficient non-blocking evented I/O. Go also transparently uses non-blocking I/O everywhere and it integrates that I/O scheduling with goroutines. non-blocking I/O where possible plus integration of the event loop into the go scheduler is, to answer our earlier question, the manner in which goroutines can be more efficient than threads and it's how go manages to be pretty good at fast networking. It's possible for a call to .Read() to submit a non-blocking I/O request and then cooperatively switch to the next goroutine much like a `async` Rust function but without having the colored function problem that often leads to library bufurication. Javascript avoids this by essentially making everything async and non-blocking. Python & Rust have to juggle async/non-async separately.

So when you combine goroutines and fully integrated non-blocking I/O that's when you get strong multicore performance and a platform that can "cheaply" handle a large number of network connections while still avoiding "callback hell" or the "function coloring" problem. It's not everyone's desired tradeoff. They've made C interop more expensive, and calls that can't be made non-blocking have to be done in a threadpool (just like node.js and DNS resolution). But if you want to productively write
some fast network servers, it's a powerful batteries included platform.
