const en = {
  title: 'Todos', done: 'done', blocked: 'blocked', more: 'more', empty: 'No todos.', noMatches: 'No matching todos.',
  expandHint: '{key} to expand', collapsed: 'collapsed', collapse: 'Collapse or expand the todo list',
  activity: 'activity', owner: 'owner', dependencies: 'depends on', metadata: 'metadata', command: 'Show the todo list',
};
export type TodoMessages = typeof en;
const translations: Record<string, TodoMessages> = {
  en,
  de: {
    title: 'Aufgaben', done: 'erledigt', blocked: 'blockiert', more: 'weitere', empty: 'Keine Aufgaben.', noMatches: 'Keine passenden Aufgaben.',
    expandHint: '{key} zum Aufklappen', collapsed: 'eingeklappt', collapse: 'Aufgabenliste ein- oder aufklappen',
    activity: 'Aktivität', owner: 'zuständig', dependencies: 'abhängig von', metadata: 'Metadaten', command: 'Aufgabenliste anzeigen',
  },
  es: {
    title: 'Tareas', done: 'completadas', blocked: 'bloqueada', more: 'más', empty: 'No hay tareas.', noMatches: 'No hay tareas coincidentes.',
    expandHint: '{key} para expandir', collapsed: 'contraído', collapse: 'Contraer o expandir la lista de tareas',
    activity: 'actividad', owner: 'responsable', dependencies: 'depende de', metadata: 'metadatos', command: 'Mostrar la lista de tareas',
  },
  fr: {
    title: 'Tâches', done: 'terminées', blocked: 'bloquée', more: 'autres', empty: 'Aucune tâche.', noMatches: 'Aucune tâche correspondante.',
    expandHint: '{key} pour développer', collapsed: 'réduit', collapse: 'Réduire ou développer la liste des tâches',
    activity: 'activité', owner: 'responsable', dependencies: 'dépend de', metadata: 'métadonnées', command: 'Afficher la liste des tâches',
  },
  pt: {
    title: 'Tarefas', done: 'concluídas', blocked: 'bloqueada', more: 'mais', empty: 'Sem tarefas.', noMatches: 'Nenhuma tarefa correspondente.',
    expandHint: '{key} para expandir', collapsed: 'recolhido', collapse: 'Recolher ou expandir a lista de tarefas',
    activity: 'atividade', owner: 'responsável', dependencies: 'depende de', metadata: 'metadados', command: 'Mostrar a lista de tarefas',
  },
  'pt-BR': {
    title: 'Tarefas', done: 'concluídas', blocked: 'bloqueada', more: 'mais', empty: 'Nenhuma tarefa.', noMatches: 'Nenhuma tarefa correspondente.',
    expandHint: '{key} para expandir', collapsed: 'recolhido', collapse: 'Recolher ou expandir a lista de tarefas',
    activity: 'atividade', owner: 'responsável', dependencies: 'depende de', metadata: 'metadados', command: 'Mostrar a lista de tarefas',
  },
  ru: {
    title: 'Задачи', done: 'выполнено', blocked: 'заблокировано', more: 'ещё', empty: 'Нет задач.', noMatches: 'Подходящих задач нет.',
    expandHint: '{key} — развернуть', collapsed: 'свёрнуто', collapse: 'Свернуть или развернуть список задач',
    activity: 'действие', owner: 'исполнитель', dependencies: 'зависит от', metadata: 'метаданные', command: 'Показать список задач',
  },
  uk: {
    title: 'Завдання', done: 'виконано', blocked: 'заблоковано', more: 'ще', empty: 'Немає завдань.', noMatches: 'Відповідних завдань немає.',
    expandHint: '{key} — розгорнути', collapsed: 'згорнуто', collapse: 'Згорнути або розгорнути список завдань',
    activity: 'дія', owner: 'виконавець', dependencies: 'залежить від', metadata: 'метадані', command: 'Показати список завдань',
  },
  zh: {
    title: '待办事项', done: '已完成', blocked: '受阻', more: '更多', empty: '暂无待办事项。', noMatches: '没有匹配的待办事项。',
    expandHint: '{key} 展开', collapsed: '已折叠', collapse: '折叠或展开待办事项',
    activity: '当前操作', owner: '负责人', dependencies: '依赖于', metadata: '元数据', command: '显示待办事项',
  },
};

export function todoMessages(locale = 'en'): TodoMessages {
  const normalized = locale.replace('_', '-');
  const key = Object.keys(translations).find(name => name.toLowerCase() === normalized.toLowerCase());
  return translations[key ?? normalized.split('-')[0]] ?? en;
}
