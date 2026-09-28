CREATE INDEX IF NOT EXISTS idx_media_relations_left_weight_right
    ON media_relations(left_media_id, weight, right_media_id);
