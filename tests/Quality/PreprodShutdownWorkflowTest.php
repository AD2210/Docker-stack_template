<?php

namespace App\Tests\Quality;

use PHPUnit\Framework\TestCase;
use Symfony\Component\Yaml\Yaml;

final class PreprodShutdownWorkflowTest extends TestCase
{
    public function testDeploymentEnvironmentIdentifiersAreAlwaysPreprodOrProd(): void
    {
        $root = dirname(__DIR__, 2);
        $promotion = Yaml::parseFile($root.'/.github/workflows/production.yaml');
        self::assertSame('prod', $promotion['jobs']['deploy-production']['with']['environment']);
        self::assertSame('prod', $promotion['jobs']['deploy-production']['with']['compose_environment']);
        $release = Yaml::parseFile($root.'/.github/workflows/release.yaml');
        self::assertSame('prod', $release['jobs']['build-production']['with']['environment']);
        foreach ([$promotion, $release] as $workflow) {
            foreach ($workflow['jobs'] as $job) {
                if (!isset($job['with']['compose_environment'])) {
                    continue;
                }
                self::assertContains($job['with']['environment'], ['preprod', 'prod']);
                self::assertSame($job['with']['environment'], $job['with']['compose_environment']);
            }
        }
    }

    public function testShutdownIsOptionalAndRunsAfterSuccessfulProductionDeployment(): void
    {
        $root = dirname(__DIR__, 2);
        $workflow = Yaml::parseFile($root.'/.github/workflows/production.yaml');
        $job = $workflow['jobs']['stop-preprod'];
        self::assertSame(['validate-promotion', 'deploy-production'], $job['needs']);
        self::assertSame("vars.STOP_PREPROD_AFTER_PROMOTION == 'true'", $job['if']);
        self::assertSame('preprod', $job['environment']);
        self::assertSame(['contents' => 'read'], $job['permissions']);
        self::assertFalse($job['concurrency']['cancel-in-progress']);
        $deployment = Yaml::parseFile($root.'/.github/workflows/_deploy.yaml');
        self::assertSame(
            str_replace('${{ inputs.environment }}', 'preprod', $deployment['jobs']['deploy']['concurrency']['group']),
            $job['concurrency']['group'],
        );
        self::assertSame('${{ needs.validate-promotion.outputs.sha }}', $job['steps'][0]['with']['ref']);
    }
}
