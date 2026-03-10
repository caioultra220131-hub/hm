export interface MarkdownPreviewBlock {
  type: 'heading' | 'paragraph' | 'list' | 'quote' | 'formula' | 'code';
  text: string;
  level: number;
}

/**
 * Keep markdown preview logic local until a full markdown and math renderer is added.
 * This keeps home summaries and editor preview stable without pulling in heavy runtime code.
 */
export class MarkdownUtils {
  static toPlainText(markdown: string): string {
    if (!markdown) {
      return '';
    }

    return markdown
      .replace(/\$\$[\s\S]*?\$\$/g, '[FormulaBlock]')
      .replace(/\$[^$\n]+\$/g, '[Formula]')
      .replace(/```[\s\S]*?```/g, '[CodeBlock]')
      .replace(/`[^`]+`/g, '[Code]')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '[Image]')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/^#{1,6}\s+/gm, '')
      .replace(/^>\s?/gm, '')
      .replace(/^\s*[-+*]\s+/gm, '')
      .replace(/^\s*\d+\.\s+/gm, '')
      .replace(/[*_~]/g, '')
      .replace(/\|/g, ' ')
      .replace(/\n+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  static preview(markdown: string, maxLength: number = 96): string {
    const plainText: string = MarkdownUtils.toPlainText(markdown);
    if (plainText.length <= maxLength) {
      return plainText;
    }
    return `${plainText.slice(0, maxLength)}...`;
  }

  static buildPreviewBlocks(markdown: string): MarkdownPreviewBlock[] {
    const lines: string[] = (markdown || '').split('\n');
    const blocks: MarkdownPreviewBlock[] = [];

    lines.forEach((line) => {
      const trimmed: string = line.trim();
      if (trimmed.length === 0) {
        return;
      }
      if (trimmed.startsWith('```')) {
        blocks.push({ type: 'code', text: 'Code snippet', level: 1 });
        return;
      }
      if (trimmed.startsWith('$$') && trimmed.endsWith('$$') && trimmed.length > 4) {
        blocks.push({ type: 'formula', text: trimmed.substring(2, trimmed.length - 2).trim(), level: 1 });
        return;
      }
      if (trimmed.startsWith('#')) {
        const level: number = Math.min(trimmed.match(/^#+/)?.[0].length ?? 1, 4);
        blocks.push({ type: 'heading', text: trimmed.replace(/^#+\s*/, ''), level });
        return;
      }
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        blocks.push({ type: 'list', text: trimmed.substring(2), level: 1 });
        return;
      }
      if (trimmed.startsWith('>')) {
        blocks.push({ type: 'quote', text: trimmed.replace(/^>\s*/, ''), level: 1 });
        return;
      }

      const inlineFormulaLine: string = trimmed.replace(/\$([^$\n]+)\$/g, '[$1]');
      blocks.push({ type: 'paragraph', text: inlineFormulaLine, level: 1 });
    });

    if (blocks.length === 0) {
      blocks.push({ type: 'paragraph', text: 'No text content yet.', level: 1 });
    }
    return blocks;
  }
}
