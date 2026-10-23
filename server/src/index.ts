import 'fastify'; // Vercel, Fastify giriş dosyasını bu import'tan tanır
import { loadConfig } from './config.ts';
import { buildApp } from './build-app.ts';

const config = loadConfig();
const app = await buildApp(config);

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, async () => {
    await app.close();
    process.exit(0);
  });
}

await app.listen({ port: config.PORT, host: config.HOST });
