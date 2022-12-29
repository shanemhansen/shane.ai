---
title: "Load Testing Tips"
date: 2022-12-28T14:35:59-08:00
---

# Load testing tips

Over a decade plus of getting retailers ready for a smooth Black Friday I've collected a few tips, tricks, and stories
related to keeping busy applications online during big events.

In fact there's one simple (not easy!) trick to it: the best way to ensure your website can handle a big
event is to have your website handle a big event. That may seem like a tautology, but it's where this post
starts and it's where it ends.

## Background

Why should you care what I have to say on load testing? I've spent a decade so far doing this for
everyone from Walmart to Google and that's left me with a bunch of fun war stories I can package up as "best practices". Odds
are some of the edge cases I've ran into will be something you'll run into too and maybe if we're lucky something here will help you avoid an outage.

## How *not* to load test

Load testing seems simple enough, but it's a fractal of emergent complexity. To paraphrase the old saying about
backups: "customers don't care about load tests, they care about the application working when they need it". It's surprisingly
easy to create load tests that give results that bear no relation to the user experience. I should know because
I've written my share of them.

Here's an example of a basic load test. Despite all the flaws we'll discuss, I often start here due to ease of use.

```sh
$ wrk -t1 -c 10 -d10 'https://example.com/'
Running 10s test @ https://example.com/
  1 threads and 10 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    25.00ms   13.04ms 230.48ms   92.26%
    Req/Sec   135.68     49.04   202.00     78.79%
  1341 requests in 10.00s, 644.14KB read
  Non-2xx or 3xx responses: 1341
Requests/sec:    134.08
Transfer/sec:     64.41KB
```

[wrk](https://github.com/wg/wrk) is a reasonably good tool for generating HTTP request load. The above code uses one
thread and 10 connections to make requests for 10 seconds. I'm going to refer to this example a couple times to show how small
changes to your load testing agent can have a big impact on your results.

### Caching

If your application has caching and your load test just hammers one single URL repeatedly, it's very likely you could get
artificially high cache hit rates and low latency. For an ecommerce application there's often a very long tail of low traffic
product page requests that don't have a very high cache hit rate. It's not unusual to have a 10x difference in performance
for cached vs uncached responses. The above `wrk` test is a perfect example of that.

There are various ways to fix this, but they depend on the application and CDN configuration. It's possible to
add cache-control headers to request the server disable a cache (in fact when you Ctrl-F5 refresh this is what your browser does). It's also possible to add cache busting query strings via timestamp. But it's up to you whether you want to test the
cached path, the uncached path, or as is most common: the cached path for your expected cache hit ratio and traffic distribution.

### Compression

Doing compression wrong is another very frequent mistake. Most customers who interact with your web app using a browser support gzip compression (some of them support brotli). Overall for text payloads like HTML/JSON/JS/CSS gzip compression provides huge bandwidth savings. In addition many CDNs either store responses gzipped to save space, or they store gzipped and non-gzipped responses separately (the relevant part of the HTTP spec involves the Vary header `Vary: Accept-Encoding`). Compression can throw off your test results in 2 ways.

1. You might be bandwidth limited during your tests if you forget to use a client that supports compression.
2. I've seen people get poor performance when using clients that don't support compression with a CDN that stores a single canonical gzip compressed copy of content, resulting in constant unzipping on the fly.

Avoiding this is generally as simple as ensuring your client sends the  `Accept-Encoding: gzip` header. For more advanced tests you might want to simulate multiple clients so that you can test gzip and brotli and ensure that cache forking on the 2 methods isn't reducing your overall cache hit rate.

During one large load test at Walmart we were both saturating bandwidth in one area and also seeing unexpectedly high CPU utilization on the cache servers. Because they stored cached text content normalized using gzip. It turned out the load agents were not configured to indicate gzip support. Which caused the cache servers to spend lots of CPU unzipping as well as waste lots of bandwidth. What at first seemed like a successful load test (at least from the pov of the team trying to find system limits) was in fact testing the wrong thing.

### Connection management

Connection management is "how requests get mapped onto underlying transports". Are you using HTTP/1.1? HTTP/2? HTTP/3? With or without TLS? Keepalive? The answer affects how much load you'll be able to generate on the applications vs the infrastructure between your client and the app. Here's why those questions matter:

#### HTTP Protocol versions

In the early days of HTTP servers closed the TCP connection to indicate a response was complete. One connection served one request. The problem was that TCP connections can be expensive to setup (See: [TCP Handshake](https://developer.mozilla.org/en-US/docs/Glossary/TCP_handshake) ). TLS < 1.2 handshakes even more so. To be honest I'm not 100% sure about TLS1.3. It gets weird with early data and I'm not going to try to go into that because I don't understand it yet.

Anyways developers quickly came up with a way to reuse connections by sending the `Content-Length` response header which allowed a client to know when a response was done. Then a new request could be sent on the connection if both the server and client had sent a [keep-alive](https://en.wikipedia.org/wiki/Keepalive) header. When combined with connection pooling this allowed clients to have several concurrent requests multiplexed onto several TCP connections. This was standardized in HTTP/1.1, along with some fixes for streaming content.

Until recently HTTP/1.1 was the protocol used by default when a CDN connected to your website origin, although as of writing this blog I see that both Google [Media CDN](https://cloud.google.com/media-cdn/docs/origins) and [Cloudflare CDN](https://developers.cloudflare.com/cache/how-to/enable-http2-to-origin/) support HTTP/2 to origin as well although it appears some other popular CDNs such as Akamai [do not](https://myakamai.force.com/customers/s/question/0D54R00007GkHvvSAF/does-akamai-support-http2-between-edge-to-origin?language=en_US). HTTP/2 addresses some of the problems of HTTP/1.1 by allowing multiple request/responses to be sent concurrently over the same connection. Although you could send multiple requests with HTTP/1.1 you generally had to wait for a response before you sent a new request (ignoring [pipelining](https://en.wikipedia.org/wiki/HTTP_pipelining) which is rarely used). This leads to a problem called [head of line blocking](https://en.wikipedia.org/wiki/Head-of-line_blocking) wherein delays in processing a single request will hold up all the others. The biggest change in HTTP/2 is that multiple connections are no longer needed and it generally runs over TLS (The TCP only version of HTTP/2 is not as well supported). However it can still suffer from head of line blocking because TCP delivers packets in order so one dropped packet means everything on the multiplexed connection stalls. There's also HTTP/3 which is built on top of UDP which enables [HTTP/3 to solve](https://calendar.perfplanet.com/2020/head-of-line-blocking-in-quic-and-http-3-the-details/#sec_http3) the head of line blocking problem.


#### Connection configuration tips

Here's what this means for performance testing:

If you don't use keepalive you'll create tons of TCP connections. That's good if you want to test your load balancer and find out how well you've tuned your TCP stack on the load generating machines. In all likelihood you will quickly exhaust your ephemeral ports if you do a naive test w/o keepalive. Personally I'd likely use HTTP/1.1 over TLS with keepalive for most application load testing. Ideally you want to use what your customers use which is usually HTTP/2, but HTTP/2 support in load testing tools can be spotty, and depending on your CDN/Load Balancer setup odds are you're speaking HTTP/1.1 to origin anyways.

You can increase that port range on linux systems as well as allow the kernel to more quickly recycle ports with the following command:

```sh
echo 1024 65535 > /proc/sys/net/ipv4/ip_local_port_range
sysctl -w net.ipv4.tcp_tw_reuse = 1
```

Here's a skeleton of a `wrk` command that does keepalive and compression over HTTP/1.1 correctly.

```sh
# wrk defaults to keepalive
wrk -c $CONNECTION_COUNT -t $THREADS -d $DURATION \
	-H 'Accept-Encoding: gzip' 'https://website/'
```

Like everything else in engineering, there are tradeoffs. The single best load test you could do would be to have agents everywhere your customers are making connections and requests exactly like your customers. There are some ways to do that, but just as normal software testing involves running fast unit tests more frequently and slower integration tests less often, a good load testing strategy often involves frequent tests with something like `wrk` and less frequent high fidelity tests across multiple regions. Most of the time I want to use just a few connections to hammer the application, but occasionally I want to make sure the TCP side of the stack is up to snuff.


### Unrepresentative client locations

This is a really broad one, but what happens is that generally your customers are all over your country or possibly all over the world. Quite often a load test is being run from a single region. This can distort results in all sorts of fun ways such as:

#### CDN Pop Overload

Your CDN likely routes customers to the closest PoP (Point of Presence). Your load test could overload a single PoP and leave the rest of the CDN and your datacenters with no traffic. Many engineers accidentally load test CDN hot spot mitigation paths, not their app.

#### Unbalanced network traffic

It is very possible that if all load is coming from a single region, parts along the way can get overloaded. As an example many load balancers doing some form of [ECMP](https://en.wikipedia.org/wiki/Equal-cost_multi-path_routing) will direct traffic based on some hash of connection information which can result in hot spots if there aren't enough connections. Similarly intermediate routers can be overloaded. For that reason I recommend using multiple load generating agents.

From a practical perspective I like to use something like [Cloud Run](https://cloud.google.com/run) because it scales to 0 based on traffic so it's pretty cheap to deploy a container to every single region.

At one point Walmart load tests seemed to hit a ceiling. We couldn't push load any higher, but paradoxically none of the systems handling the load seemed to be at saturation. We ruled out CPU/RAM and bandwidth to individual machines. We went back and checked our work to verify multi-core scalability and came up with nothing. It was unfortunately a stressful time with many teams grasping at straws to figure out the culprit. One of the most interesting clues was that the ceiling happened at a suspiciously round number. Let's say 4Gbps. After a lot of investigation that probably deserves it's own post I realized that we had 2 circuits coming into our DC (lest you think the fact this happened on-prem means you don't have to worry: customers using the Cloud at large scales have lots of analogous things like interconnects and gateways). Theoretically we should have had 2 20Gbps links and they shouldn't have been saturated. After picking up a phone and calling the guy who was responsible for purchasing those I found out from him that: "we just brought the new one online, I wonder if the ISP left it at 2Gbps". Which it turns out was the case. One phone call later and we were back in business. Some fraction of our TCP flows from our load testing agents were going to through the under provisioned link and that was creating artificial back pressure on the load testing agents. It just goes to show the importance of monitoring on all your dependencies physical or virtual. I've seen the same sort of issues with naively written cloud NAT "appliances" (linux vms) that lack monitoring of `nf_conntrack` table size, resulting in mostly-silent degradation.

This has informed my performance monitoring philosophy which is an extension of my unit testing philosophy.

> If there's not a test proving it works, it doesn't.

and

> If you're not monitoring performance, it's degraded.


### Unrealistic traffic

Here's a very common story at large retailers. Someone runs a load test. The app passes with flying colors. Organic traffic begins to ramp up. The website crashes. What happened?

Well it turns out naive load tests often fail to exercise critical components. Here's just a handful of ways I've seen this happen:

The load test was detected as a bot and all those super fast 200 responses were captcha pages. Nobody bothered to verify that the page under test was returning the correct content. I wish I could tell a war story here, but there's probably too many to choose from.

> If you're not asserting you're getting the expected content, you're not.

The load test pulled down a product page (eg `https://example.com/product/123`) but since this is a SPA (Single Page App) all the important API calls happened via `fetch`/`XHR` and so all the load test really did was pull down an empty shell of a page.


The load test pulled down all the HTML, but none of the associated resources such as images/css/javascript etc. More than once in my career I've seen developers put timestamp cache busters on their static content, only to cause an outage when they deploy and every single request from customers is a cache miss (eg `https://example.com/static/image.jpg?_=$(date +%s)`).


## How to create load tests that give you confidence your web app will scale

What you want is to simulate a bunch of real customers doing a bunch of realistic things on your web app. Real customers come from different locations. They use different browsers. They look at different products. They do things like search/login/add to chart/checkout/etc. They execute javascript and download images. They use browsers that [support HTTP/2](https://caniuse.com/http2) or [HTTP/3](https://caniuse.com/http3). Of course running a load test with chrome is a lot more resource intensive than running a load test with `wrk`, just like an end to end integration test is more expensive than a unit test.

I recommend you start out with benchmarks alongside your repo's unit tests. These should be ran frequently and tracked in your metrics system. For every release you should know how the behavior of core endpoints like `GET /resource/foo` behaves under load, possibly with mocked data store or API dependencies. Problems found here are cheapest to fix. In Go this looks like something using the [httptest](https://pkg.go.dev/net/http/httptest) package and their [Benchmark](https://pkg.go.dev/testing#hdr-Benchmarks) package. Now it's often the case that the team writing load tests is not the app development team, but SRE best practices show that cross functional teams co-developing features results in fewer big issues during launch. A trivial-ish example might look like:


```go
func BenchmarkApp(b *testing.B) {
 b.RunParallel(func(pb *testing.PB) {
     handler := MyNewApplicationHandler()
     for pb.Next() {
	     req := httptest.NewRequest("GET", "http://example.com/foo", nil)
		 w := httptest.NewRecorder()
	     handler(w, req)
		 // validate response recorder `w` returns 200 and correct content
	 }
 })
}
```

The next layer up is "simple" scripted CLI load tests. I like `wrk` with lua scripting which can do a pretty good job of hitting a bunch of random URLs quickly and defeating caching if needed. It doesn't support http/2 but [go-wrk](https://github.com/tsliwowicz/go-wrk) does. Properly configured with compression support this is a great workhorse for individual teams to test their critical endpoints. You can also do more complicated tests such as requesting a resource and then dependent resources but that can take a lot of work and knowledge of the application to capture the right requests to make. People often use Siege here or even Apache Jmeter.

Here's an example with `wrk` (adapted from [Intelligent benchmark with wrk](https://medium.com/@felipedutratine/intelligent-benchmark-with-wrk-163986c1587f) ) which randomly selects between 1000 product URLs. Lua scripting is very powerful here for creating custom benchmark scenarios.

```lua
math.randomseed(os.time())
request = function() 
	url_path = "/product/" .. math.random(0,1000)
	return wrk.format("GET", url_path)
end
```

You would use this script like:

```sh
wrk -c10 -t1 -d10s -H 'Accept-Encoding: gzip' -s ./wrk.lua
```

Finally for full scale high fidelity load tests there are relatively few tools out there for browser based load testing. Unfortunately the automation frameworks out there such as selenium can be fragile and have lots of overhead and so [they discourage using their libraries for load testing](https://www.selenium.dev/documentation/test_practices/discouraged/performance_testing/).

There are essentially three approaches I like to use.

The first one feels like cheating but after several years preparing Walmart for Black Friday I can attest to it's unreasonable effectiveness. Before your big event (such as Black Friday) hold some sort of flash sale/small event. For example one year there was a highly anticipated low-quantity device that had just been released. My company stocked a few on their website and sent out an email marketing blast and instantly generated the best load test money can buy as customers flocked to the website to get a good deal. We of course had a minor outage and then had time to optimize and fix before Black Friday/Cyber Monday. If you can run some sort of test marketing event before the big event you absolutely should.

On the more technical side: it's possible to record a real customer interaction and export HAR (http archive) files. Those can be [imported into something like jmeter](https://www.flood.io/blog/convert-har-files-to-jmeter-test-plans), or you can write your own converter. I haven't tried this approach yet.

My preferred approach at the moment is to use headless chrome on cloud run to generate load from multiple regions. With a little scripting in [chromedriver](https://chromedriver.chromium.org/home) it's possible to load a bunch of pages, take screenshots, and export all the timing metrics for later processing. I use [Cloud Workflows](https://cloud.google.com/workflows) to orchestrate the process and take care of ramping up traffic and collecting summary statistics. I'm working on open sourcing my workflows/containers here to allow others to easily spin up real-browser load tests. Stay tuned.
