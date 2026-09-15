<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

/**
 * Exposes the lightweight readiness endpoint used by Docker and GitHub Actions.
 *
 * The endpoint intentionally avoids database or service dependencies so the
 * deploy workflow can check that FrankenPHP and Symfony boot after Compose and
 * Caddy have switched to the new release.
 */
final class HealthController extends AbstractController
{
    /**
     * Returns an empty 200 response when the application kernel is reachable.
     */
    #[Route('/health', name: 'app_health')]
    public function healthcheck(): JsonResponse
    {
        return new JsonResponse(status: 200);
    }
}
