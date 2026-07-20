import fs from 'node:fs';
import path from 'node:path';
import { THESIS_SECTIONS } from '../sections';

describe('THESIS_SECTIONS', () => {
  it('espelha ThesisItem::SECTIONS do backend', () => {
    const model = fs.readFileSync(
      path.resolve(process.cwd(), 'app/models/thesis_item.rb'),
      'utf8'
    );
    const match = model.match(/SECTIONS = %w\[([^\]]+)\]/);
    expect(match).toBeTruthy();
    expect(THESIS_SECTIONS).toEqual(match[1].split(/\s+/).filter(Boolean));
  });
});
