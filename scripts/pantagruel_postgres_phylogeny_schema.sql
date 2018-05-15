CREATE SCHEMA phylogeny;

SET search_path = phylogeny;

CREATE TABLE phylogeny.species_tree (
  branch_id SMALLINT PRIMARY KEY,
  parent_branch_id SMALLINT,
  branch_name VARCHAR(50) DEFAULT NULL,   -- only for tips and clade/populationancestors
  is_tip BOOL 
);

CREATE TYPE phylogeny.eventtype AS ENUM ('D', 'T', 'S', 'SL', 'L', 'O');

CREATE TABLE phylogeny.species_tree_events (
  event_id INT PRIMARY KEY,
  event_type eventtype NOT NULL,
  don_branch_id SMALLINT,          -- refers to species_tree (branch_id)
  rec_branch_id SMALLINT NOT NULL  -- refers to species_tree (branch_id)
);

CREATE INDEX ON species_tree_events (event_type);

CREATE TABLE phylogeny.gene_lineage_events ( --to be a large table
  event_id SERIAL,
  cds_code VARCHAR(50) NOT NULL,   -- refers to genome.coding_sequences (cds_code)
  freq INT NOT NULL,
  reconciliation_id SMALLINT       -- to distinguish reconciliation sets; can be NULL if not to be redundant
);

CREATE TABLE phylogeny.reconciliations (
  reconciliation_id SMALLINT NOT NULL,
  reconciliation_name VARCHAR NOT NULL,
  reconciliation_date TIMESTAMP
);

-- after filling the tables

CREATE INDEX ON gene_lineage_events (reconciliation_id);
CREATE INDEX ON gene_lineage_events (cds_code);
CREATE INDEX ON gene_lineage_events (event_id);
CREATE INDEX ON gene_lineage_events (freq);
ALTER TABLE gene_lineage_events ADD PRIMARY KEY (event_id, cds_code, reconciliation_id);