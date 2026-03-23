"""widen api_keys key_prefix to 25 chars

Revision ID: 8a09e0e2e034
Revises: 5a6864e1b335
Create Date: 2026-03-23 22:49:36.748571

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8a09e0e2e034'
down_revision: Union[str, Sequence[str], None] = '5a6864e1b335'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        # SQLite doesn't enforce VARCHAR length — column already works, just stamp
        pass
    else:
        op.alter_column('api_keys', 'key_prefix',
                   existing_type=sa.VARCHAR(length=12),
                   type_=sa.String(length=25),
                   existing_nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    bind = op.get_bind()
    if bind.dialect.name == "sqlite":
        pass
    else:
        op.alter_column('api_keys', 'key_prefix',
                   existing_type=sa.String(length=25),
                   type_=sa.VARCHAR(length=12),
                   existing_nullable=False)
