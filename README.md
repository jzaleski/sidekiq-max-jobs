sidekiq-max-jobs
================

A [Sidekiq](https://sidekiq.org/) server middleware. Requires `sidekiq >= 4.0.0`

This gem provides the ability to configure the maximum number of jobs a `Worker`
will process before terminating. For an environment running _Kubernetes_ this is
a perfect addition because once the affected pod dies it will automatically be
restarted resetting memory, database-connections, etc. with minimal interruption
to processing throughput.

Origin Story
------------

While working on a project for [HappyFunCorp](https://happyfuncorp.com/) we were
dealing with unmanageable memory growth on our primary DB. We did all the
regular things for _Sidekiq_ such as disabling prepared statements, running with
uncached queries, etc. to no avail. After lots of Googling, like any dilligent
developer does, we hit a dead-end. A number of people had seen this issue and
reported it, yet there was no real guidance aside from "restart your workers
periodically to free resources." We saw that this worked, however rather than
setting up a CRON we decided to implement a middleware that gave each `Worker`
the reigns at controlling its own fate. What started as a work-around, turned
out to actually be a pretty good solution vs. switching to a different
background-job processing framework. Given that others are facing the same / a
similar issue, we wanted to give it back to the open-source community.

Install & Quick Start
---------------------

To install:
```bash
$ gem install sidekiq-max-jobs
```

If you're using [Bundler](https://bundler.io/) to manage your dependencies you
should add the following to your Gemfile:
```ruby
gem 'sidekiq-max-jobs'
```

Next, add the middleware to your `sidekiq` initializer (typically: config/initializers/sidekiq.rb)
```ruby
require 'sidekiq/middleware/server/max_jobs'
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Sidekiq::Middleware::Server::MaxJobs
  end
end
```

If everything above is successful the next time you start your worker you will
see a message like the following:
```bash
2020-06-10T00:23:31.789Z pid=73703 tid=oxifk6l13 INFO: Max-Jobs middleware enabled, shutting down pid: 73703 when quota is reached
```

Configuration Options
---------------------

Above we covered how to get started, but that's only the beginning. There are a
few configuration options available to you to customize the middleware's
behavior (currently only configurable via the environment):

* `MAX_JOBS`: The number of jobs to process before terminating (default: `500`)
* `MAX_JOBS_JITTER`: Used as the upper-bound for calculating a random number
between 1 and the value specified. This value is added to the `MAX_JOBS` value,
mentioned above, to decrease the likelihood that all of your `Worker(s)`
restart at / around the same time (default: `rand(-1)`)
* `MAX_JOBS_<QUEUE>`: The number of jobs to process for a specific queue before
terminating (default: `-1`)
* `MAX_JOBS_JITTER_<QUEUE>`: Used as the upper-bound for calculating a random
number between 1 and the value specified. This value is added to the
`MAX_JOBS_<QUEUE>` value, mentioned above, to decreased the likelihood that all
of your `Worker(s)` restart at / around the same time (default:
`rand(-1)`)
* `MAX_JOBS_RUNTIME`: The total time in seconds to run before terminating
(default: `-1`)
* `MAX_JOBS_RUNTIME_JITTER`: Used as the upper-bound for calculating a random
number between 1 and the value specified. This value is added to the
`MAX_JOBS_RUNTIME` value, mentioned above, to decrease the likelihood that all
of your `Worker(s)` restart at / around the same time (default: `rand(-1)`)

Important Note
--------------

When determining if the max-job quota has been reached the runtime is checked
first, followed by the total jobs processed, followed by the jobs processed for
the current queue. If your `Worker(s)` are handling multiple queues it is
recommended that you set the total value to the same value as your highest queue
value (e.g. if you had `MAX_JOBS_FOO=100` and `MAX_JOBS_BAR=200` it probably
makes sense to set `MAX_JOBS=200`, if not a little bit lower). Setting the right
limits ultimately depends on the intensity / resource needs of the work being
performed. The same rule of thumb applies to `MAX_JOBS_JITTER` as well.

Contributing
------------

1. Fork it (http://github.com/jzaleski/sidekiq-max-jobs/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
