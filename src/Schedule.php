<?php

namespace App;

use Symfony\Component\Scheduler\Attribute\AsSchedule;
use Symfony\Component\Scheduler\Schedule as SymfonySchedule;
use Symfony\Component\Scheduler\ScheduleProviderInterface;
use Symfony\Contracts\Cache\CacheInterface;

/**
 * Provides the application's recurring task registry.
 *
 * The schedule is stateful so missed runs survive worker restarts during
 * deploys, while processOnlyLastMissedRun prevents a long outage from replaying
 * a backlog of stale periodic work.
 */
#[AsSchedule]
class Schedule implements ScheduleProviderInterface
{
    /**
     * @param CacheInterface $cache Shared cache pool used by Symfony Scheduler to persist run state
     */
    public function __construct(
        private CacheInterface $cache,
    ) {
    }

    /**
     * Builds the default schedule consumed by the scheduler worker.
     */
    public function getSchedule(): SymfonySchedule
    {
        return (new SymfonySchedule())
            ->stateful($this->cache)
            ->processOnlyLastMissedRun(true)

            // add your own tasks here
            // see https://symfony.com/doc/current/scheduler.html#attaching-recurring-messages-to-a-schedule
        ;
    }
}
