-- ============================================================================
-- SETUP INICIAL — DAROCHA PAINEL
-- ============================================================================
-- Cria todas as tabelas iniciais, RLS, trigger handle_new_user e seed
-- da Telecall (cliente, posts, campanhas).
-- ============================================================================

-- TABELAS

CREATE TABLE IF NOT EXISTS profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  name        TEXT NOT NULL DEFAULT '',
  role        TEXT NOT NULL DEFAULT 'cliente' CHECK (role IN ('admin','editor','cliente')),
  client_id   BIGINT,
  avatar_url  TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS clients (
  id            BIGSERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  slug          TEXT NOT NULL UNIQUE,
  primary_color TEXT DEFAULT '#0066b3',
  logo_url      TEXT,
  active        BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE profiles ADD CONSTRAINT profiles_client_id_fkey
  FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS posts (
  id                BIGSERIAL PRIMARY KEY,
  client_id         BIGINT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  date              DATE NOT NULL,
  time              TIME NOT NULL DEFAULT '10:00',
  format            TEXT NOT NULL,
  pillar            TEXT NOT NULL,
  instagram         TEXT,
  linkedin          TEXT,
  briefing_summary  TEXT,
  briefing_full     JSONB,
  status            TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS campaigns (
  id              BIGSERIAL PRIMARY KEY,
  client_id       BIGINT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  platform        TEXT NOT NULL CHECK (platform IN ('linkedin','meta','google')),
  name            TEXT NOT NULL,
  description     TEXT,
  objective       TEXT,
  format          TEXT,
  budget_cents    BIGINT NOT NULL DEFAULT 0,
  start_date      DATE NOT NULL,
  end_date        DATE NOT NULL,
  briefing_full   JSONB,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ads (
  id            BIGSERIAL PRIMARY KEY,
  campaign_id   BIGINT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  code          TEXT,
  headline      TEXT,
  description   TEXT,
  format        TEXT,
  placement     TEXT,
  cta           TEXT,
  budget_cents  BIGINT DEFAULT 0,
  start_date    DATE,
  end_date      DATE,
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS comments (
  id          BIGSERIAL PRIMARY KEY,
  post_id     BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  text        TEXT NOT NULL,
  author_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS replies (
  id          BIGSERIAL PRIMARY KEY,
  comment_id  BIGINT NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  post_id     BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  text        TEXT NOT NULL,
  author_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reactions (
  id          BIGSERIAL PRIMARY KEY,
  comment_id  BIGINT REFERENCES comments(id) ON DELETE CASCADE,
  reply_id    BIGINT REFERENCES replies(id) ON DELETE CASCADE,
  post_id     BIGINT REFERENCES posts(id) ON DELETE CASCADE,
  emoji       TEXT NOT NULL,
  author_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (comment_id, reply_id, emoji, author_id)
);

CREATE TABLE IF NOT EXISTS campaign_comments (
  id           BIGSERIAL PRIMARY KEY,
  campaign_id  BIGINT REFERENCES campaigns(id) ON DELETE CASCADE,
  ad_id        BIGINT REFERENCES ads(id) ON DELETE CASCADE,
  text         TEXT NOT NULL,
  author_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS media (
  id            BIGSERIAL PRIMARY KEY,
  client_id     BIGINT REFERENCES clients(id) ON DELETE SET NULL,
  post_id       BIGINT REFERENCES posts(id) ON DELETE CASCADE,
  campaign_id   BIGINT REFERENCES campaigns(id) ON DELETE CASCADE,
  ad_id         BIGINT REFERENCES ads(id) ON DELETE CASCADE,
  storage_path  TEXT NOT NULL,
  url           TEXT NOT NULL,
  type          TEXT NOT NULL,
  name          TEXT,
  size_bytes    BIGINT,
  uploaded_by   UUID REFERENCES profiles(id),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS comment_attachments (
  id            BIGSERIAL PRIMARY KEY,
  comment_id    BIGINT REFERENCES comments(id) ON DELETE CASCADE,
  reply_id      BIGINT REFERENCES replies(id) ON DELETE CASCADE,
  storage_path  TEXT NOT NULL,
  url           TEXT NOT NULL,
  type          TEXT NOT NULL,
  name          TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- HELPER FUNCTIONS

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin');
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.is_editor_or_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','editor'));
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.user_client_id()
RETURNS BIGINT AS $$
  SELECT client_id FROM profiles WHERE id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Versão original de can_see_client (substituída pelo SQL 05)
CREATE OR REPLACE FUNCTION public.can_see_client(target_client_id BIGINT)
RETURNS BOOLEAN AS $$
  SELECT public.is_editor_or_admin() OR public.user_client_id() = target_client_id;
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ENABLE RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE media ENABLE ROW LEVEL SECURITY;
ALTER TABLE comment_attachments ENABLE ROW LEVEL SECURITY;

-- POLICIES (versões originais; algumas atualizadas pelos SQLs 04, 05 e 06)

CREATE POLICY "Ver próprio profile" ON profiles FOR SELECT
  USING (id = auth.uid() OR is_editor_or_admin());

CREATE POLICY "Visualização de clientes" ON clients FOR SELECT
  USING (is_editor_or_admin() OR user_client_id() = id);
CREATE POLICY "Admin gerencia clientes" ON clients FOR ALL
  USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Visualizar posts do meu cliente" ON posts FOR SELECT
  USING (can_see_client(client_id));
CREATE POLICY "Editor/admin cria posts" ON posts FOR INSERT WITH CHECK (is_editor_or_admin());
CREATE POLICY "Editor/admin edita posts" ON posts FOR UPDATE USING (is_editor_or_admin());
CREATE POLICY "Admin exclui posts" ON posts FOR DELETE USING (is_admin());

CREATE POLICY "Ver campanhas do cliente" ON campaigns FOR SELECT
  USING (can_see_client(client_id));
CREATE POLICY "Editor/admin gerencia campanhas" ON campaigns FOR ALL
  USING (is_editor_or_admin()) WITH CHECK (is_editor_or_admin());

CREATE POLICY "Ver anúncios" ON ads FOR SELECT
  USING (EXISTS (SELECT 1 FROM campaigns WHERE campaigns.id = ads.campaign_id AND can_see_client(campaigns.client_id)));
CREATE POLICY "Editor/admin gerencia anúncios" ON ads FOR ALL
  USING (is_editor_or_admin()) WITH CHECK (is_editor_or_admin());

CREATE POLICY "Ver comentários" ON comments FOR SELECT
  USING (EXISTS (SELECT 1 FROM posts WHERE posts.id = comments.post_id AND can_see_client(posts.client_id)));
CREATE POLICY "Comentar" ON comments FOR INSERT WITH CHECK (true);
CREATE POLICY "Admin exclui comentários" ON comments FOR DELETE USING (is_admin());

CREATE POLICY "Ver replies" ON replies FOR SELECT
  USING (EXISTS (SELECT 1 FROM posts WHERE posts.id = replies.post_id AND can_see_client(posts.client_id)));
CREATE POLICY "Responder" ON replies FOR INSERT WITH CHECK (true);
CREATE POLICY "Admin exclui replies" ON replies FOR DELETE USING (is_admin());

CREATE POLICY "Ver reações" ON reactions FOR SELECT
  USING (EXISTS (SELECT 1 FROM posts WHERE posts.id = reactions.post_id AND can_see_client(posts.client_id)));
CREATE POLICY "Reagir" ON reactions FOR INSERT WITH CHECK (true);
CREATE POLICY "Remover própria reação" ON reactions FOR DELETE USING (author_id = auth.uid());

CREATE POLICY "Ver coments de campanha" ON campaign_comments FOR SELECT
  USING (
    (campaign_id IS NOT NULL AND EXISTS (SELECT 1 FROM campaigns WHERE campaigns.id = campaign_comments.campaign_id AND can_see_client(campaigns.client_id)))
    OR
    (ad_id IS NOT NULL AND EXISTS (SELECT 1 FROM ads JOIN campaigns ON campaigns.id = ads.campaign_id WHERE ads.id = campaign_comments.ad_id AND can_see_client(campaigns.client_id)))
  );
CREATE POLICY "Comentar em campanha" ON campaign_comments FOR INSERT WITH CHECK (true);
CREATE POLICY "Admin exclui coment campanha" ON campaign_comments FOR DELETE USING (is_admin());

CREATE POLICY "Visualizar mídia" ON media FOR SELECT USING (can_see_client(client_id));
CREATE POLICY "Editor/admin sobe mídia" ON media FOR INSERT WITH CHECK (is_editor_or_admin());
CREATE POLICY "Editor/admin remove mídia" ON media FOR DELETE USING (is_editor_or_admin());

-- BUCKETS (devem ser criados via UI do Supabase Storage):
--   media (público)
--   attachments (público)
--   client-logos (público)
