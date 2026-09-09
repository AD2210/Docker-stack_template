<?php

declare(strict_types=1);

namespace App\Tests\Quality;

use PHPUnit\Framework\TestCase;
use Symfony\Component\Process\Process;

final class QualityToolingTest extends TestCase
{
    private string $temporary;

    protected function setUp(): void
    {
        $this->temporary = sys_get_temp_dir().'/prospection-quality-'.bin2hex(random_bytes(8));
        mkdir($this->temporary.'/bin', 0700, true);
    }

    protected function tearDown(): void
    {
        $files = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($this->temporary, \FilesystemIterator::SKIP_DOTS), \RecursiveIteratorIterator::CHILD_FIRST);
        foreach ($files as $file) {
            if ($file->isDir()) {
                rmdir($file->getPathname());
            } else {
                unlink($file->getPathname());
            }
        }
        rmdir($this->temporary);
    }

    public function testReleaseValidationRejectsUnsafeTagsBeforeGitAndResolvesCommit(): void
    {
        $this->mock('git', <<<'SH'
printf '%s\n' "$*" >> "$TEST_LOG"
if [[ "$1" == rev-parse ]]; then printf '%040d\n' 7; fi
if [[ "$1" == merge-base ]]; then exit "${ANCESTRY_STATUS:-0}"; fi
SH);
        foreach (['v1.2.3', 'V01.2.3', 'V1.2.3-rc.1', 'V1.2', '--upload-pack=x', 'V1.2.3/../../x'] as $invalid) {
            self::assertSame(1, $this->runCommand(['bash', $this->root().'/.github/scripts/resolve-release.sh', $invalid])->getExitCode());
        }
        self::assertFileDoesNotExist($this->temporary.'/calls');
        $process = $this->runCommand(['bash', $this->root().'/.github/scripts/resolve-release.sh', 'V1.2.3']);
        self::assertTrue($process->isSuccessful(), $process->getErrorOutput());
        self::assertStringContainsString('sha='.str_repeat('0', 39).'7', $process->getOutput());
        self::assertStringContainsString('refs/tags/V1.2.3^{commit}', (string) file_get_contents($this->temporary.'/calls'));
        self::assertSame(1, $this->runCommand(['bash', $this->root().'/.github/scripts/resolve-release.sh', 'V1.2.3'], ['ANCESTRY_STATUS' => '1'])->getExitCode());
    }

    public function testDeploymentRecordsOnlyAfterBackupAndHealth(): void
    {
        foreach (['server-release', 'sudo', 'docker', 'curl', 'tar', 'setfacl'] as $command) {
            $this->mock($command, <<<'SH'
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TEST_LOG"
if [[ "$(basename "$0")" == docker && "$1" == login ]]; then
    cat >/dev/null
    printf '%s' "$DOCKER_CONFIG" > "$TEST_LOG.registry"
    printf 'fake-token' > "$DOCKER_CONFIG/config.json"
fi
if [[ "$(basename "$0")" == docker && "$*" == *'config --format json'* ]]; then
    printf '%s\n' '{"name":"prospection-quality-test","services":{"php":{"image":"old"},"messenger":{"image":"old"},"scheduler":{"image":"old"}}}'
fi
if [[ "$(basename "$0")" == "${FAIL_COMMAND:-none}" ]]; then exit 9; fi
if [[ -n "${FAIL_MATCH:-}" && "$*" == *"$FAIL_MATCH"* ]]; then exit 9; fi
SH);
        }
        mkdir($this->temporary.'/app/secrets', 0700, true);
        file_put_contents($this->temporary.'/app/secrets/postgres_password', 'test-db-only');
        file_put_contents($this->temporary.'/app/secrets/preprod.decrypt.private.php', 'test-key-only');
        copy($this->root().'/Makefile', $this->temporary.'/app/Makefile');
        mkdir($this->temporary.'/app/deploy');
        copy($this->root().'/.github/scripts/render-runtime.py', $this->temporary.'/app/deploy/render-runtime.py');
        $env = [
            'APP_PATH' => $this->temporary.'/app', 'COMPOSE_PROJECT_NAME' => 'prospection-quality-test',
            'COMPOSE_ENVIRONMENT' => 'preprod', 'RELEASE_TAG' => 'V0.1.0', 'RELEASE_SERVICE' => 'php',
            'RELEASE_IMAGE' => 'ghcr.io/example/app-php-preprod', 'GHCR_USERNAME' => 'test',
            'GHCR_TOKEN' => 'test-only', 'APP_URL' => 'https://preprod.example.invalid',
        ];
        foreach (['sudo', 'docker', 'curl'] as $failure) {
            file_put_contents($this->temporary.'/calls', '');
            $process = $this->runCommand(['bash', $this->root().'/.github/scripts/remote-deploy.sh'], $env + ['FAIL_COMMAND' => $failure]);
            self::assertNotSame(0, $process->getExitCode(), $process->getErrorOutput());
            self::assertStringNotContainsString('server-release record', (string) file_get_contents($this->temporary.'/calls'));
        }
        foreach (['--entrypoint php --user 33'] as $failure) {
            file_put_contents($this->temporary.'/calls', '');
            $process = $this->runCommand(['bash', $this->root().'/.github/scripts/remote-deploy.sh'], $env + ['FAIL_MATCH' => $failure]);
            self::assertNotSame(0, $process->getExitCode(), $process->getErrorOutput());
            $failedCalls = (string) file_get_contents($this->temporary.'/calls');
            self::assertStringNotContainsString('server-release record', $failedCalls);
            if ('--entrypoint php --user 33' === $failure) {
                self::assertStringNotContainsString('stop messenger scheduler', $failedCalls);
            }
        }
        file_put_contents($this->temporary.'/calls', '');
        $process = $this->runCommand(['bash', $this->root().'/.github/scripts/remote-deploy.sh'], $env);
        self::assertTrue($process->isSuccessful(), $process->getErrorOutput());
        $calls = (string) file_get_contents($this->temporary.'/calls');
        $previous = -1;
        foreach (['server-release init', 'sudo /usr/local/lib/server-setup/backup-databases.sh', 'tar -xzf', '--entrypoint php --user 33', 'stop messenger scheduler', 'up --detach --wait --remove-orphans', 'curl ', 'server-release record'] as $marker) {
            $position = strpos($calls, $marker);
            self::assertNotFalse($position, $marker);
            self::assertGreaterThan($previous, $position, $marker);
            $previous = $position;
        }
        self::assertStringContainsString('/health', $calls);
        self::assertStringContainsString('is_readable($path)', $calls);
        self::assertSame('test-db-only', file_get_contents($this->temporary.'/app/secrets/postgres_password'));
        self::assertSame('test-key-only', file_get_contents($this->temporary.'/app/secrets/preprod.decrypt.private.php'));
        self::assertDirectoryDoesNotExist((string) file_get_contents($this->temporary.'/calls.registry'));
        self::assertSame([], glob($this->temporary.'/app/.candidate.*'));
        self::assertSame([], glob($this->temporary.'/app/.runtime.*'));
        self::assertSame([], glob($this->temporary.'/app/.resolved.*'));
        self::assertFileExists($this->temporary.'/app/compose.runtime.yaml');
        $manifest = json_decode((string) file_get_contents($this->temporary.'/app/compose.runtime.yaml'), true, flags: JSON_THROW_ON_ERROR);
        self::assertSame('prospection-quality-test', $manifest['name']);
        self::assertStringContainsString('PHP_SHA_CURRENT', $manifest['services']['php']['image']);
        unlink($this->temporary.'/app/secrets/postgres_password');
        file_put_contents($this->temporary.'/calls', '');
        self::assertFalse($this->runCommand(['bash', $this->root().'/.github/scripts/remote-deploy.sh'], $env)->isSuccessful());
        self::assertSame('', file_get_contents($this->temporary.'/calls'));
    }

    public function testDeploymentUsesOnlySshSecretsAndAutomaticRegistryCredentials(): void
    {
        $workflow = (string) file_get_contents($this->root().'/.github/workflows/_deploy.yaml');
        preg_match_all('/secrets\.([A-Z_]+)/', $workflow, $matches);
        $names = array_values(array_unique($matches[1]));
        sort($names);
        self::assertSame(['GITHUB_TOKEN', 'SSH_HOST', 'SSH_KNOWN_HOSTS', 'SSH_PORT', 'SSH_PRIVATE_KEY', 'SSH_USER'], $names);
        preg_match_all('/vars\.([A-Z_]+)/', $workflow, $matches);
        self::assertSame(['APP_PATH', 'APP_URL'], $matches[1]);
        self::assertStringContainsString('${{ github.actor }}', $workflow);
        self::assertStringContainsString('StrictHostKeyChecking=yes', $workflow);
        self::assertStringContainsString('ssh -p "$SSH_PORT"', $workflow);
        self::assertStringContainsString('scp -P "$SSH_PORT"', $workflow);
        self::assertStringNotContainsString('${BUNDLE}/secrets', $workflow);
    }

    public function testRegistryGateOnlyAcceptsConfirmedNotFound(): void
    {
        $this->mock('curl', <<<'SH'
cat >/dev/null
if [[ "$*" == *ghcr.io/token* ]]; then
    printf '%s\n' '{"token":"test-token"}'
else
    printf '%s\n' "$*" >> "$TEST_LOG"
    printf '%s' "${REGISTRY_STATUS:-404}"
fi
SH);
        foreach (['404' => 0, '200' => 1, '403' => 1, '500' => 1] as $status => $expected) {
            $process = $this->runCommand(['bash', $this->root().'/.github/scripts/assert-image-absent.sh', 'ghcr.io/example/app', 'V0.1.0'], [
                'GHCR_USERNAME' => 'test', 'GHCR_TOKEN' => 'test_only', 'REGISTRY_STATUS' => (string) $status,
            ]);
            self::assertSame($expected, $process->getExitCode(), $process->getErrorOutput());
        }
        self::assertStringContainsString('https://ghcr.io/v2/example/app/manifests/V0.1.0', (string) file_get_contents($this->temporary.'/calls'));
    }

    public function testSshPortValidationRejectsInvalidValues(): void
    {
        $workflow = \Symfony\Component\Yaml\Yaml::parseFile($this->root().'/.github/workflows/_deploy.yaml');
        $validation = '';
        foreach ($workflow['jobs']['deploy']['steps'] as $step) {
            if ('Validate deployment configuration' === ($step['name'] ?? '')) {
                foreach (explode("\n", $step['run']) as $line) {
                    if (str_contains($line, 'SSH_PORT')) {
                        $validation = $line;
                    }
                }
            }
        }
        self::assertNotSame('', $validation);
        foreach (['1', '22', '2222', '65535'] as $port) {
            self::assertTrue($this->runCommand(['bash', '-c', $validation], ['SSH_PORT' => $port])->isSuccessful());
        }
        foreach (['', '0', '65536', '999999999999', '-1', '022', '22; echo invalid', 'abc'] as $port) {
            self::assertFalse($this->runCommand(['bash', '-c', $validation], ['SSH_PORT' => $port])->isSuccessful());
        }
    }

    private function root(): string
    {
        return dirname(__DIR__, 2);
    }

    private function mock(string $name, string $body): void
    {
        $path = $this->temporary.'/bin/'.$name;
        file_put_contents($path, "#!/usr/bin/env bash\nset -euo pipefail\n".$body."\n");
        chmod($path, 0700);
    }

    /** @param list<string> $command
     * @param array<string, string> $environment
     */
    private function runCommand(array $command, array $environment = []): Process
    {
        $process = new Process($command, $this->root(), $environment + [
            'PATH' => $this->temporary.'/bin:'.getenv('PATH'),
            'TEST_LOG' => $this->temporary.'/calls',
        ]);
        $process->setTimeout(10);
        $process->run();

        return $process;
    }
}
