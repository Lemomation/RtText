# Supabase backend artifacts

## Applying the migration

Project ref: `jskzgedrciwklcmmpwcx`

With the Supabase CLI:

```bash
supabase link --project-ref jskzgedrciwklcmmpwcx
supabase db push
```

Or open `supabase/migrations/0001_init.sql` in the Supabase dashboard
(SQL Editor) and run it.

## Deploying the edge function

```bash
supabase functions deploy ai-reply --project-ref jskzgedrciwklcmmpwcx
supabase secrets set GEMMA_API_KEY=<google-ai-studio-key> --project-ref jskzgedrciwklcmmpwcx
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected automatically into edge functions.

## Notes

- `bots.sys_prompt` is never exposed to clients: `SELECT` on `public.bots` is
  restricted to the owner via RLS, and anonymous/authenticated reads go
  through the `public_bots` view, which omits `sys_prompt` and only returns
  public bots (or the caller's own bots).
- Realtime is enabled on `conversations` and `messages`.
- Storage bucket `pfp` is public; authenticated users may upload under
  `user/<uid>/*` or `bot/*` prefixes.
