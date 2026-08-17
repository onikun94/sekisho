import { Hono } from 'hono';
import { authRoutes } from './routes/auth';
import { accountRoutes } from './routes/account';
import { ApiError } from './errors';
import type { Env } from './env';

const app = new Hono<{ Bindings: Env }>();

app.get('/healthz', (c) => c.json({ status: 'ok' }));

app.route('/v1/auth', authRoutes);
app.route('/v1/account', accountRoutes);

app.notFound((c) => c.json({ error: { code: 'not_found', message: 'not found' } }, 404));

app.onError((error, c) => {
  if (error instanceof ApiError) {
    return c.json({ error: { code: error.code, message: error.message } }, error.status as 400);
  }
  console.error('unhandled error', error);
  return c.json({ error: { code: 'internal_error', message: 'internal server error' } }, 500);
});

export default app;
