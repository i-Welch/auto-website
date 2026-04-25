import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';

export * from './schema';

export type Db = ReturnType<typeof createDb>;

export function createDb(url: string) {
  const client = postgres(url, { prepare: false, max: 10 });
  return drizzle(client, { schema, casing: 'snake_case' });
}
