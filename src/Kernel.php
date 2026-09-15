<?php

namespace App;

use Symfony\Bundle\FrameworkBundle\Kernel\MicroKernelTrait;
use Symfony\Component\HttpKernel\Kernel as BaseKernel;

/**
 * Boots the Symfony application with the framework's default micro-kernel.
 *
 * Keeping the kernel thin preserves the template upgrade path: project-specific
 * wiring should live in config files and services rather than in custom boot code.
 */
class Kernel extends BaseKernel
{
    use MicroKernelTrait;
}
